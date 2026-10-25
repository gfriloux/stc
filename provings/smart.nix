# Proving: SMART relic
# Boots a VM with a SATA disk that answers SMART and asserts that smartd's own
# alerts reach notifyCommand with the documented environment — the wrapper is
# never run by hand.
#
# QEMU's SATA disk (ide-hd on the q35 AHCI bus) reports health, attributes and a
# temperature of 31 °C. The node lowers the critical temperature to 30 °C, so
# smartd raises a real Temperature alert at its first check, and adds `-M test`
# for the startup test message. The disk is a null-co block device: no image
# file, reads return zeroes.
#
# The relic is not wired into any cogitator, so this proving imports it alone.
# `virtonly` has the relic on and only the virtio root disk: smartd finds
# nothing to watch and its unit fails — the cloud caveat in the docs.
{self}: let
  relic = {
    imports = [self.nixosModules.relics-smart];
    stc.relics.smart = {
      enable = true;
      hostname = "smart-proving";
      notifyCommand = ''
        printf '%s|%s|%s|%s\n' "$STC_SMART_FAILTYPE" "$STC_SMART_DEVICE" \
          "$STC_SMART_HOSTNAME" "$STC_SMART_MESSAGE" >> /run/stc-smart-alerts
        # Output goes to the journal, not back to smartd.
        echo "delivered $STC_SMART_FAILTYPE"
      '';
    };
  };
in {
  name = "smart";

  nodes.machine = {
    imports = [relic];
    virtualisation.qemu.options = [
      "-blockdev driver=null-co,node-name=smart0,size=67108864,read-zeroes=on"
      "-device ide-hd,drive=smart0,serial=STCSMART0"
    ];
    stc.relics.smart.defaults = "-a -W 0,0,30 -M test";
  };

  nodes.virtonly = {
    imports = [relic];
  };

  testScript = ''
    start_all()

    with subtest("smartd's alerts reach notifyCommand"):
        machine.wait_for_unit("smartd.service")
        machine.wait_until_succeeds("grep -q '^EmailTest|' /run/stc-smart-alerts")
        machine.wait_until_succeeds("grep -q '^Temperature|' /run/stc-smart-alerts")
        alerts = machine.succeed("cat /run/stc-smart-alerts")
        print(alerts)
        for line in alerts.splitlines():
            failtype, device, host, message = line.split("|", 3)
            # SMARTD_DEVICESTRING, not the bare SMARTD_DEVICE.
            assert device == "/dev/sda [SAT]", line
            assert host == "smart-proving", line
            assert message, line
        machine.wait_until_succeeds(
            "journalctl -t stc-smart-notify --no-pager | grep -q 'delivered Temperature'"
        )

    with subtest("one alert path: no upstream channel in smartd.conf"):
        conf = machine.succeed(
            "systemctl cat smartd | grep -o -- '--configfile=[^ ]*' | cut -d= -f2 | xargs cat"
        )
        print(conf)
        execs = [l for l in conf.splitlines() if "-M exec" in l]
        assert execs and all("stc-smart-notify" in l for l in execs), conf
        assert "smartd-notify.sh" not in conf, conf

    with subtest("smartd writes its state under /var/lib/smartmontools"):
        # The package has no savestates default: this file exists only because
        # the relic passes --savestates.
        machine.succeed("ls /var/lib/smartmontools/smartd.QEMU_HARDDISK-STCSMART0.ata.state")

    with subtest("no SMART disk: the unit fails instead of watching nothing"):
        virtonly.wait_until_succeeds("systemctl is-failed smartd.service")
        # virtonly keeps the relic's default `defaults`, so 17 also proves that
        # string parses: a syntax error exits with another code.
        # 17 is smartd's "no device to monitor" exit, not some other failure.
        status = virtonly.succeed("systemctl show -P ExecMainStatus smartd.service").strip()
        assert status == "17", status
        virtonly.fail("test -e /run/stc-smart-alerts")
  '';
}
