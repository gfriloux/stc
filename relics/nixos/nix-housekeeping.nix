# Relic: Nix Housekeeping
#
# Keeps a long-lived host's Nix store and journal bounded without anyone
# watching the disk:
#
#   - scheduled GC (nix.gc): retention, so old generations do not pile up;
#   - min-free / max-free: GC *during* a build when free space runs low. This
#     is what prevents `No space left on device` in the middle of a remote
#     `nixos-rebuild switch`; the GC timer only catches up afterwards. The two
#     solve different problems and are not redundant — drop either and one of
#     them is missing;
#   - store optimisation on a timer (nix.optimise.automatic), NOT
#     nix.settings.auto-optimise-store: the latter hashes every freshly built
#     path inline and taxes every switch, for the same deduplication;
#   - builds that yield to what the machine serves (deprioritiseBuilds);
#   - a journal cap: container logs land in the journal, and without a cap the
#     only bound is the disk.
#
# Defaults suit a server (the conservative case: a 30-day rollback window).
# cogitator/nixos/vm.nix narrows keepDays for a throwaway VM.
#
# Deliberately left out when the #59 lot was scoped (srvos sets both):
# nix.gc.randomizedDelaySec, and a `--max-freed` GC mode — the build-time
# pressure valve is min-free/max-free here.
#
# Every third-party setting is written with mkDefault: the relic's own options
# are the knobs, and a consumer writing nix.gc.options or a journald key
# directly should win without mkForce rather than hit a conflict.
{
  config,
  lib,
  ...
}: let
  cfg = config.stc.relics.nixHousekeeping;
  gib = n: n * 1024 * 1024 * 1024;

  # Without Nix (an appliance image with nix.enable = false) there is no store
  # or daemon to tend: upstream asserts that nix.gc / nix.optimise need
  # nix.enable, so the store-side settings would be a build error, not a no-op.
  # In a container the store is the host's: its GC, its deduplication and its
  # disk pressure are the host's business (and nixpkgs' container-config.nix
  # writes `nix.optimise.automatic = mkDefault false` there — a second mkDefault
  # saying true would be a conflict error). The journal is the machine's own
  # either way.
  hasNix = config.nix.enable;
  ownsStore = hasNix && !config.boot.isContainer;
in {
  options.stc.relics.nixHousekeeping = {
    enable = lib.mkEnableOption "bounded Nix store and journal for a long-lived host";

    gc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run Nix garbage collection on a timer (`nix.gc.automatic`).";
      };
      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "When to run the GC (systemd calendar expression).";
      };
      keepDays = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 30;
        description = ''
          Delete store paths, and the generations that hold them, older than
          this many days. 30 days is a server's rollback window; a throwaway VM
          can afford less.
        '';
      };
    };

    minFreeGiB = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = 5;
      description = ''
        When free space on the store drops below this many GiB during a build,
        Nix collects garbage until `maxFreeGiB` is free (`nix.settings.min-free`).
        `null` leaves both settings to Nix, which never collects during a build.
      '';
    };

    maxFreeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      description = ''
        How much free space, in GiB, a build-time collection stops at
        (`nix.settings.max-free`). Must be above `minFreeGiB`. Ignored when
        `minFreeGiB` is `null`.
      '';
    };

    optimise = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Deduplicate the store on a timer (`nix.optimise.automatic`). Upstream
        already runs it at idle CPU and IO priority.
      '';
    };

    deprioritiseBuilds = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let builds and garbage collection yield to the services the machine
        runs:

        - the Nix daemon, and so every build, runs with CPU policy `batch`
          and IO class `best-effort` at its lowest priority (7). Not `idle`:
          upstream warns that `idle` can starve a configuration update on a
          loaded machine, which on a server is the rebuild you need;
        - the daemon gets `OOMScoreAdjust=250`, so under memory pressure the
          kernel kills a build before a served process;
        - the scheduled GC runs with CPU policy `batch` and IO class `idle`.
      '';
    };

    journal = {
      systemMaxUse = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "500M";
        description = "journald `SystemMaxUse`. `null` leaves journald's own (10% of the filesystem, up to 4G).";
      };
      maxRetentionSec = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "1month";
        description = "journald `MaxRetentionSec`. `null` leaves journald's own (no time limit).";
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = cfg.minFreeGiB == null || cfg.maxFreeGiB > cfg.minFreeGiB;
          message = ''
            stc.relics.nixHousekeeping.maxFreeGiB (${toString cfg.maxFreeGiB}) must be
            above minFreeGiB (${toString cfg.minFreeGiB}): a build-time collection
            starts below minFree and stops once maxFree is free.
          '';
        }
      ];
    }

    (lib.mkIf (ownsStore && cfg.gc.enable) {
      nix.gc = {
        automatic = lib.mkDefault true;
        dates = lib.mkDefault cfg.gc.dates;
        options = lib.mkDefault "--delete-older-than ${toString cfg.gc.keepDays}d";
      };
    })

    (lib.mkIf (ownsStore && cfg.minFreeGiB != null) {
      nix.settings = {
        min-free = lib.mkDefault (gib cfg.minFreeGiB);
        max-free = lib.mkDefault (gib cfg.maxFreeGiB);
      };
    })

    (lib.mkIf (ownsStore && cfg.optimise) {
      nix.optimise.automatic = lib.mkDefault true;
    })

    (lib.mkIf (hasNix && cfg.deprioritiseBuilds) {
      nix = {
        daemonCPUSchedPolicy = lib.mkDefault "batch";
        daemonIOSchedClass = lib.mkDefault "best-effort";
        daemonIOSchedPriority = lib.mkDefault 7;
      };
      systemd.services.nix-daemon.serviceConfig.OOMScoreAdjust = lib.mkDefault 250;
      # nix-gc exists whenever nix.enable, timer or not (nixpkgs nix-gc.nix), so
      # this is safe with gc.enable off — and hasNix above is that same
      # condition, so no stub unit is created without Nix.
      systemd.services.nix-gc.serviceConfig = {
        CPUSchedulingPolicy = lib.mkDefault "batch";
        IOSchedulingClass = lib.mkDefault "idle";
      };
    })

    (lib.mkIf (cfg.journal.systemMaxUse != null) {
      services.journald.settings.Journal.SystemMaxUse = lib.mkDefault cfg.journal.systemMaxUse;
    })

    (lib.mkIf (cfg.journal.maxRetentionSec != null) {
      services.journald.settings.Journal.MaxRetentionSec = lib.mkDefault cfg.journal.maxRetentionSec;
    })
  ]);
}
