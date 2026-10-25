# Relic: SMART
#
# Runs smartd over every SMART-capable disk and hands each alert to a
# consumer-supplied command. The ZFS relic sees a pool once a disk has failed;
# SMART sees reallocated sectors, pending sectors and temperature before that.
#
# Transport-agnostic, like relics/nixos/docker/notify.nix: STC owns smartd and
# its configuration, not the notification backend. The consumer provides
# `notifyCommand`, which receives everything through the environment:
#   STC_SMART_DEVICE    — the device, as smartd names it ("/dev/sda [SAT]")
#   STC_SMART_MESSAGE   — smartd's one-line message
#   STC_SMART_FAILTYPE  — Health, Usage, Temperature, … or EmailTest for -M test
#   STC_SMART_HOSTNAME  — the host, for message titles
#
# Upstream's own channels (mail, wall, x11) are turned off. Each one adds its
# own `-M exec` to smartd.conf, and wall is on by default; nobody reads a wall
# on a headless server, and two exec directives would leave one of them unused.
# They are defaults, so the assertion below explains the conflict instead of a
# bare "conflicting definitions" error.
#
# smartd keeps state across restarts under /var/lib/smartmontools (the package
# is built without a savestates default). Without it, every reboot re-sends the
# standing warnings and forgets when the next self-test is due. Side effect,
# per smartd.conf(5): with state on, the reminder default is `-M daily`, not
# `-M once` — a standing problem (pending sectors, heat) is re-sent every day
# until it is fixed. Kept: on a host nobody logs into, one alert is easy to miss.
#
# smartd blocks until the exec returns and reads any output as a sign of
# trouble (smartd.conf(5), -M exec). So the command runs under a timeout, and
# its output goes to the journal rather than back to smartd: a stalled webhook
# must not freeze every SMART check, and ntfy's JSON reply is not an error.
#
# A disk with no SMART — a virtio or cloud disk — gives smartd nothing to watch,
# and smartd then exits: the unit fails. That is deliberate. A monitor that runs
# with nothing to watch would read as coverage. Hence opt-in, and no cogitator
# enables it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.stc.relics.smart;
  upstream = config.services.smartd.notifications;

  commandScript = pkgs.writeShellScript "stc-smart-notify-command" cfg.notifyCommand;

  notifyScript = pkgs.writeShellScript "stc-smart-notify" ''
    export STC_SMART_DEVICE="$SMARTD_DEVICESTRING"
    export STC_SMART_MESSAGE="$SMARTD_MESSAGE"
    export STC_SMART_FAILTYPE="$SMARTD_FAILTYPE"
    export STC_SMART_HOSTNAME=${lib.escapeShellArg cfg.hostname}

    # systemd-cat runs the command with its output in the journal. Not a pipe
    # into it: with no command, systemd-cat execs /bin/cat, absent on NixOS.
    exec ${config.systemd.package}/bin/systemd-cat -t stc-smart-notify \
      ${pkgs.coreutils}/bin/timeout ${toString cfg.notifyTimeoutSec} ${commandScript}
  '';

  # A `-M exec` the consumer writes anywhere smartd reads silently replaces the
  # relic's (smartd only logs "ignoring previous mail Directive"), and
  # notifyCommand never runs. Counted on the strings that reach smartd.conf.
  execCount = str: lib.length (lib.splitString "-M exec" str) - 1;
  smartdCfg = config.services.smartd;
  # The relic's one exec lives in `monitored` (the DEFAULT line). `autodetected`
  # may repeat it verbatim — its upstream default — but carry no other; device
  # lines inherit DEFAULT and carry none.
  singleExec =
    execCount smartdCfg.defaults.monitored
    == 1
    && (!smartdCfg.autodetect
      || smartdCfg.defaults.autodetected == smartdCfg.defaults.monitored
      || execCount smartdCfg.defaults.autodetected == 0)
    && lib.all (d: execCount d.options == 0) smartdCfg.devices;

  stateDir = "/var/lib/smartmontools";
in {
  imports = [./state.nix];

  options.stc.relics.smart = {
    enable = lib.mkEnableOption "SMART disk monitoring with smartd";

    autodetect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Monitor every SMART-capable device present when smartd starts, without
        naming disks per host. Set to false to monitor only
        services.smartd.devices.
      '';
    };

    defaults = lib.mkOption {
      type = lib.types.str;
      default = "-a -o on -S on -s (S/../.././02|L/../../6/03) -W 4,45,55";
      description = ''
        smartd.conf directives applied to every device (see smartd.conf(5)).
        The default:
          -a             every health check, attribute and log
          -o on -S on    the drive's offline data collection and attribute autosave
          -s (…)         short self-test daily at 02:00, long one Saturday at 03:00
          -W 4,45,55     report a 4 °C jump, log at 45 °C, alert at 55 °C
        The relic adds the notification directives itself.
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "Hostname exposed to notifyCommand as STC_SMART_HOSTNAME.";
    };

    notifyCommand = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = lib.literalExpression ''
        '''
          ''${pkgs.curl}/bin/curl -s \
            --max-time 10 \
            -H "Title: [$STC_SMART_HOSTNAME] $STC_SMART_FAILTYPE on $STC_SMART_DEVICE" \
            -d "$STC_SMART_MESSAGE" \
            "https://ntfy.sh/$(cat ''${config.sops.secrets."ntfy/topic".path})"
        '''
      '';
      description = ''
        Shell snippet run for each smartd alert. Receives through the
        environment:
          STC_SMART_DEVICE    — the device, as smartd names it
          STC_SMART_MESSAGE   — smartd's message
          STC_SMART_FAILTYPE  — the alert type (EmailTest for a -M test message)
          STC_SMART_HOSTNAME  — value of the `hostname` option

        STC is agnostic to the notification backend: put your ntfy curl,
        webhook POST, e-mail, etc. here, and read any secret it needs from its
        own file. Required when the relic is enabled.

        smartd waits for it, so it runs under notifyTimeoutSec; its output goes
        to the journal under the tag stc-smart-notify.
      '';
    };

    notifyTimeoutSec = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = ''
        Seconds notifyCommand may run before it is killed. smartd blocks while
        the command runs, so a stalled endpoint would otherwise stop every
        SMART check.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.notifyCommand != "";
        message = ''
          stc.relics.smart.enable is true but notifyCommand is empty. A disk
          monitor that tells no one reads as coverage that does not exist. Set
          stc.relics.smart.notifyCommand to the shell command that delivers the
          alert (it receives STC_SMART_DEVICE, STC_SMART_MESSAGE,
          STC_SMART_FAILTYPE and STC_SMART_HOSTNAME in the environment).
        '';
      }
      {
        assertion = !(upstream.mail.enable || upstream.wall.enable || upstream.x11.enable);
        message = ''
          stc.relics.smart delivers smartd alerts through notifyCommand, but
          services.smartd.notifications.{mail,wall,x11}.enable is set to true.
          Each of them adds its own `-M exec` to smartd.conf, beside the relic's.
          Turn them off and send the mail (or anything else) from notifyCommand.
        '';
      }
      {
        assertion = singleExec;
        message = ''
          stc.relics.smart found a second `-M exec` in smartd's directives
          (stc.relics.smart.defaults, services.smartd.defaults.* or a
          services.smartd.devices entry). smartd keeps only the last one, so
          notifyCommand would never run. Remove it and deliver the alert from
          notifyCommand.
        '';
      }
    ];

    services.smartd = {
      enable = true;
      inherit (cfg) autodetect;
      # DEFAULT carries it to every device line and to DEVICESCAN; upstream's
      # `autodetected` falls back to `monitored` and only repeats it.
      defaults.monitored = "-m <nomailer> -M exec ${notifyScript} ${cfg.defaults}";
      extraOptions = ["--savestates=${stateDir}/smartd."];
      notifications = {
        mail.enable = lib.mkDefault false;
        wall.enable = lib.mkDefault false;
        x11.enable = lib.mkDefault false;
      };
    };

    systemd.services.smartd.serviceConfig.StateDirectory = "smartmontools";

    stc.relics.state.paths = [
      {
        path = stateDir;
        type = "directory";
        description = "smartd's per-disk state: attribute history, temperature extremes, the last warning sent and the next self-test due. Without it, smartd re-sends standing warnings after a restart.";
        kind = "cache";
      }
    ];
  };
}
