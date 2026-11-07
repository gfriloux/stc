# Proving: AppArmor relic
# Boots two VMs with AppArmor and Docker and runs the same containers on both.
# `confined` has the relic; `upstream` has security.apparmor.enable alone, the
# stock NixOS way. Docker reports docker-default on both — only the relic makes
# it real.
#
# The image is a busybox built by dockerTools: the test VM has no network, so
# nothing is pulled.
#
# The discriminating action, measured: `mount -t tmpfs` with CAP_SYS_ADMIN.
# The capability lets the seccomp filter through, so the only thing left to
# refuse the mount is docker-default's `deny mount`. A container run with
# `--security-opt apparmor=unconfined` and the same capability mounts, which
# proves the denial is AppArmor's and nothing else's.
#
# `upstream` is the witness: the day its container reads docker-default,
# NixOS fixed it and the relic's Docker half can go.
#
# The relic is not enabled by any cogitator, so this proving imports it alone.
{self}: let
  image = pkgs:
    pkgs.dockerTools.buildImage {
      name = "stc-proving-apparmor";
      tag = "latest";
      copyToRoot = [pkgs.busybox];
      config.Cmd = ["sleep" "3600"];
    };

  # Both nodes load and run the same image the same way.
  docker = {pkgs, ...}: {
    virtualisation.docker.enable = true;
    environment.systemPackages = [pkgs.apparmor-bin-utils];
    environment.etc."stc-proving-apparmor.tar".source = image pkgs;
  };
in {
  name = "apparmor";

  nodes.confined = {
    imports = [self.nixosModules.relics-hardening-apparmor docker];
    stc.relics.hardening.apparmor.enable = true;
  };

  nodes.upstream = {
    imports = [docker];
    security.apparmor.enable = true;
  };

  testScript = ''
    mount = "sh -c 'mkdir -p /m && mount -t tmpfs none /m'"

    def run(m):
        m.wait_for_unit("docker.service")
        m.succeed("docker load < /etc/stc-proving-apparmor.tar")
        m.succeed("docker run -d --name dflt --cap-add SYS_ADMIN stc-proving-apparmor:latest")
        m.succeed(
            "docker run -d --name unc --cap-add SYS_ADMIN"
            " --security-opt apparmor=unconfined stc-proving-apparmor:latest"
        )

    def attr(m, c):
        return m.succeed(f"docker exec {c} cat /proc/1/attr/current").strip()

    start_all()

    with subtest("the relic: containers run under docker-default, enforced"):
        run(confined)
        assert attr(confined, "dflt") == "docker-default (enforce)", attr(confined, "dflt")
        status = confined.succeed("aa-status")
        print(status)
        assert "docker-default" in status, status

    with subtest("the relic: docker-default denies what the capability allows"):
        out = confined.fail(f"docker exec dflt {mount} 2>&1")
        assert "Permission denied" in out, out
        # Same capability, profile off: the mount goes through.
        assert attr(confined, "unc") == "unconfined", attr(confined, "unc")
        confined.succeed(f"docker exec unc {mount}")

    with subtest("the relic: a reload of AppArmor leaves running containers confined"):
        # What a switch that changes /etc/apparmor.d runs. Without the relic's
        # docker-default name there, aa-remove-unknown unloads the profile and
        # the running container turns unconfined.
        confined.succeed("systemctl reload apparmor.service")
        assert attr(confined, "dflt") == "docker-default (enforce)", attr(confined, "dflt")
        # Docker's profile, not the never-loaded stub: an empty profile would
        # deny the exec itself.
        out = confined.fail(f"docker exec dflt {mount} 2>&1")
        assert "Permission denied" in out, out

    with subtest("upstream alone: Docker names the profile, the kernel never loads it"):
        run(upstream)
        profile = upstream.succeed("docker inspect -f '{{.AppArmorProfile}}' dflt").strip()
        assert profile == "docker-default", profile
        assert attr(upstream, "dflt") == "unconfined", attr(upstream, "dflt")
        upstream.succeed(f"docker exec dflt {mount}")
  '';
}
