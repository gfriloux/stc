# Proving: vm cogitator
# Boots the base dev/staging profile and asserts the four things it claims: a
# primary user that can actually administer the box, remote access, bounded
# store growth, and Docker *off* unless asked for.
#
# Two nodes on purpose. The cogitator documents that membership of the `docker`
# group is equivalent to root — "so it is opt-in rather than a silent default".
# A single node could only prove one half of that sentence: `machine` proves the
# group and the daemon are absent by default, `dockervm` proves the opt-in path
# wires both. Their closures are nearly identical, so the cost is one extra VM
# boot.
#
# Scope note — nothing here asserts a mount. The qemu-vm module replaces the
# whole `fileSystems` set with `mkVMOverride`, so filesystem claims cannot be
# read inside a test VM (see the hardening proving for the full rationale).
{self}: {
  name = "vm";

  nodes = {
    machine = {
      imports = [self.nixosModules.cogitator-vm];
      stc.cogitator.vm.enable = true;
    };

    dockervm = {
      imports = [self.nixosModules.cogitator-vm];
      stc.cogitator.vm = {
        enable = true;
        docker.enable = true;
      };
    };
  };

  testScript = ''
    start_all()

    machine.wait_for_unit("multi-user.target")

    with subtest("primary user can administer the box"):
        groups = machine.succeed("id -nG admin").split()
        assert "wheel" in groups, f"admin is not in wheel: {groups}"
        # The other half of the opt-in claim is on the dockervm node below.
        # Without this line a silent default would satisfy every assertion here.
        assert "docker" not in groups, f"admin is in docker without opting in: {groups}"

        shell = machine.succeed("getent passwd admin").strip().split(":")[-1]
        assert shell.endswith("/bin/fish"), f"unexpected login shell: {shell}"
        # The shell has to work, not merely be recorded in passwd: a store path
        # that is not in the closure would still pass the assertion above.
        machine.succeed("su -l admin -c 'echo $FISH_VERSION' | grep -q .")

    with subtest("user services survive logout"):
        # users.manageLingering applies linger from linger-users.service, which
        # calls loginctl — there are no tmpfiles rules to read. That unit is a
        # Type=oneshot with no RemainAfterExit, wantedBy multi-user.target: by
        # the time the target is up it has already run and gone back to
        # "inactive (dead)". So `wait_for_unit` can never pass here — assert the
        # result and the marker it left instead.
        result = machine.succeed(
            "systemctl show -p Result --value linger-users.service"
        ).strip()
        assert result == "success", f"linger-users.service result: {result}"
        machine.succeed("test -f /var/lib/systemd/linger/admin")

    with subtest("remote access"):
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(22)

    with subtest("store growth is bounded"):
        gc_timer = machine.succeed("systemctl cat nix-gc.timer")
        assert "OnCalendar=weekly" in gc_timer, f"unexpected gc schedule:\n{gc_timer}"

        # keepDays ends up inside the generated unit script, not in ExecStart, so
        # resolve the script and read it — the same technique the docker-server
        # proving uses to reach the rendered `docker run` line.
        unit = machine.succeed("systemctl cat nix-gc.service")
        exec_start = [
            line.split("=", 1)[1].strip()
            for line in unit.splitlines()
            if line.startswith("ExecStart=")
        ]
        assert len(exec_start) == 1, f"expected one ExecStart, got {exec_start}"
        script = machine.succeed(f"cat {exec_start[0].split()[0]}")
        assert "--delete-older-than 5d" in script, f"unexpected gc options:\n{script}"

        # Deduplication is a separate timer; the profile turns both on.
        machine.succeed("systemctl cat nix-optimise.timer")

    with subtest("flakes are usable"):
        nix_conf = machine.succeed("cat /etc/nix/nix.conf")
        assert "experimental-features = nix-command flakes" in nix_conf, nix_conf

    with subtest("docker is opt-in"):
        # No unit at all, not merely a stopped one.
        machine.fail("systemctl cat docker.service")
        machine.fail("test -e /run/docker.sock")

    with subtest("docker opt-in wires the daemon and the group"):
        dockervm.wait_for_unit("multi-user.target")

        groups = dockervm.succeed("id -nG admin").split()
        assert "docker" in groups, f"admin was not added to docker: {groups}"

        dockervm.wait_for_unit("docker.service")
        dockervm.succeed("docker info")
        # docker-compose rides on the same option — the profile adds it to
        # systemPackages only on this path.
        dockervm.succeed("docker-compose --version")
  '';
}
