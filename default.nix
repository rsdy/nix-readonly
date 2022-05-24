let
  msize = 154857600;

  runner = pkgs: name: system: "${pkgs.screen}/bin/screen -S ${name} -dm -- sh -c ${system.config.system.build.rootless-vm}/bin/run";

  mkMount = device: {
    inherit device;
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "noexec" "nodev" "nosuid" "msize=${toString msize}" "cache=none" ];
    neededForBoot = true;
  };

  mkExecMount = device: {
    inherit device;
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "msize=${toString msize}" "cache=none" ];
    neededForBoot = true;
  };

  createSystem =
    { hostName, domain, mountPoints, zfsVolumeRoot, memorySize, cores, hostMTU, lib, ... }@args':
    let
      fqdn = "${hostName}.${domain}";
      startVM = { config, pkgs, ... }@args:
        let
          vmDir = "${zfsVolumeRoot}/${fqdn}";
          zfsVolBase = "${vmDir}/mounts";
          rwHostBase = "/${zfsVolBase}";

          zfsName = mount: "${zfsVolBase}/${mount.device}";
          localPath = mount: "${rwHostBase}/${mount.device}";
          mountToLocal = mount: " -virtfs local,path=${localPath mount},security_model=passthrough,mount_tag=${mount.device}";
          createLocalZFS = mount: "zfs list |grep -q ${zfsName mount} || zfs create -p ${zfsName mount}\n";

          persistentFileSystems = lib.concatMapStrings createLocalZFS (lib.attrValues mountPoints);
          qemuVirtfsHostMounts = lib.concatMapStrings mountToLocal (lib.attrValues mountPoints);

          regInfo = lib.closureInfo { rootPaths = config.virtualisation.pathsInNixDB; };
          qemu = pkgs.qemu_kvm;
        in
        ''
            macaddr=$(printf "52:54:%02x:%02x:%02x:%02x" $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff )) $(( $RANDOM & 0xff)) $(( $RANDOM & 0xff )) )
            echo $macaddr

            TAPDEV=tap-${hostName}

            ip tuntap add dev $TAPDEV mode tap && {
              ip link set $TAPDEV up promisc on
              ip link set dev $TAPDEV master br0
              ip link set dev $TAPDEV mtu ${toString hostMTU}
            }

            ${persistentFileSystems}

            # Start QEMU.
            exec ${qemu}/bin/qemu-system-x86_64 -enable-kvm -cpu host,invtsc=on,arch-capabilities=on,kvm-pv-eoi=off,host-phys-bits=on \
          -machine q35,accel=kvm,usb=off,dump-guest-core=off \
                -name "${fqdn}" \
                -m ${toString memorySize} \
                -smp cores=${toString cores},threads=1 \
                \
                -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny \
                -rtc base=utc,driftfix=slew \
                -global kvm-pit.lost_tick_policy=delay \
          -global ICH9-LPC.disable_s3=1 \
          -global ICH9-LPC.disable_s4=1 \
          -display none \
          -no-hpet \
          -no-user-config \
          -nodefaults \
                -overcommit mem-lock=on \
                -device intel-iommu,caching-mode=on,aw-bits=48 \
                -device pcie-root-port,port=0x8,chassis=1,id=pci.1,bus=pcie.0,multifunction=on,addr=0x1 \
                -device pcie-root-port,port=0x9,chassis=2,id=pci.2,bus=pcie.0,addr=0x1.0x1 \
                -device pcie-root-port,port=0xa,chassis=5,id=pci.5,bus=pcie.0,addr=0x1.0x2 \
                -device pcie-root-port,port=0xb,chassis=6,id=pci.6,bus=pcie.0,addr=0x1.0x3 \
                -device pcie-root-port,port=0xc,chassis=7,id=pci.7,bus=pcie.0,addr=0x1.0x4 \
                -device pcie-root-port,port=0xd,chassis=8,id=pci.8,bus=pcie.0,addr=0x1.0x5 \
                -device pcie-root-port,port=0xe,chassis=9,id=pci.9,bus=pcie.0,addr=0x1.0x6 \
                \
                -device virtio-balloon-pci,id=balloon0 \
                -netdev tap,id=net0,ifname=$TAPDEV,script=no,downscript=no,vhost=on \
                -device virtio-net-pci,mq=on,vectors=18,netdev=net0,id=net0,mac=$macaddr,bus=pcie.0,addr=0x3 \
                \
                -virtfs local,path=/nix/store,security_model=none,mount_tag=store \
               ${qemuVirtfsHostMounts} \
                \
                -kernel ${config.system.build.toplevel}/kernel \
                -initrd ${config.system.build.toplevel}/initrd \
                -append "$(cat ${config.system.build.toplevel}/kernel-params) init=${config.system.build.toplevel}/init console=ttyS0 $QEMU_KERNEL_PARAMS" \
                -monitor unix:/${vmDir}/monitor-socket,server,nowait \
                -chardev pty,id=charserial0 \
                -device isa-serial,chardev=charserial0,id=serial0 \
          -serial mon:stdio \
                $QEMU_OPTS \
                "$@"
        '';

    in

    { modulesPath, config, pkgs, ... } @ args:
    {
      nix = {
        package = pkgs.nixFlakes;
        extraOptions = ''
          experimental-features = nix-command flakes
        '';
      };

      imports = [
        "${modulesPath}/virtualisation/qemu-vm.nix"
        "${modulesPath}/profiles/qemu-guest.nix"
        ./vm-security.nix
        #"${modulesPath}/profiles/headless.nix"
        #"${modulesPath}/profiles/minimal.nix"
      ];

      system.build.rootless-vm = pkgs.runCommand "nixos-vm" { preferLocalBuild = true; }
        ''
          mkdir -p $out/bin
          ln -s ${config.system.build.toplevel} $out/system
          ln -s ${pkgs.writeScript "run-nixos-vm" (startVM args)} $out/bin/run
        '';

      networking = {
        inherit hostName domain;
        enableIPv6 = true;
        firewall.allowPing = true;
      };

      virtualisation.writableStore = false;

      boot.initrd.postDeviceCommands =
        ''
    '';

      fileSystems = lib.mkOverride 0 (
        {
          "/" =
            {
              device = "tmpfs";
              fsType = "tmpfs";
              neededForBoot = true;
            };
          "/tmp" =
            {
              device = "tmpfs";
              fsType = "tmpfs";
              neededForBoot = true;
              options = [ "mode=1777" "strictatime" "nosuid" "nodev" "noexec" ];
            };
          "/nix/store" =
            {
              device = "store";
              fsType = "9p";
              options = [ "ro" "trans=virtio" "version=9p2000.L" "cache=loose" "_netdev" "nobootwait" "msize=${toString msize}" ];
              neededForBoot = true;
            };
        } // mountPoints
      );

      security.sudo.enable = false;
      users.mutableUsers = false;
      users.users.root = {
        hashedPassword = "invalid";
      };
    };

  lib = {
    inherit
      runner
      mkMount
      mkExecMount
      createSystem
      ;
  };
in
lib
