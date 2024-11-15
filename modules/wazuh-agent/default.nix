{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  wazuhUser = "wazuh";
  wazuhGroup = wazuhUser;
  stateDir = "/var/ossec";
  cfg = config.services.wazuh-agent;
  pkg = config.services.wazuh-agent.package;

  generatedConfig =
    if !(builtins.isNull cfg.config)
    then cfg.config
    else import ./generate-agent-config.nix {
      cfg = config.services.wazuh-agent;
      inherit pkgs;
    };

  preStart = ''
    ${concatMapStringsSep "\n"
      (dir:
        "[ -d ${stateDir}/${dir} ] || cp -Rv --no-preserve=ownership ${pkg}/${dir} ${stateDir}/${dir}")
        [ "queue" "var" "wodles" "logs" "lib" "tmp" "agentless" "active-response" "etc" ]
     }

    chown -R ${wazuhUser}:${wazuhGroup} ${stateDir}

    find ${stateDir} -type d -exec chmod 770 {} \;
    find ${stateDir} -type f -exec chmod 750 {} \;

    # Generate and copy ossec.config
    cp ${pkgs.writeText "ossec.conf" generatedConfig} ${stateDir}/etc/ossec.conf

  '';

  daemons =
    ["wazuh-modulesd" "wazuh-logcollector" "wazuh-syscheckd" "wazuh-agentd" "wazuh-execd"];

  mkService = d:
    {
      description = "${d}";
      wants = [ "network-online.target" ];
      after = [ "network.target" "network-online.target" ];
      partOf = [ "wazuh.target" ];
      path = cfg.path ++ [ "/run/current-system/sw/bin" "/run/wrappers/bin" ];
      environment = {
        WAZUH_HOME = stateDir;
      };

      serviceConfig = {
        Type = "exec";
        User = wazuhUser;
        Group = wazuhGroup;
        WorkingDirectory = "${stateDir}/";
        CapabilityBoundingSet = [ "CAP_SETGID" ];

        ExecStart =
          if (d != "wazuh-modulesd")
          then "/run/wrappers/bin/${d} -f -c ${stateDir}/etc/ossec.conf"
          else "/run/wrappers/bin/${d} -f";
      };
    };

in {
  options = {
    services.wazuh-agent = {
      enable = lib.mkEnableOption "Wazuh agent";

      managerIP = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = ''
          The IP address or hostname of the manager.
        '';
        example = "192.168.1.2";
      };

      managerPort = lib.mkOption {
        type = lib.types.port;
        description = ''
          The port the manager is listening on to receive agent traffic.
        '';
        example = 1514;
        default = 1514;
      };

      package = lib.mkPackageOption pkgs "wazuh-agent" {};

      path = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [];
        example = lib.literalExpression "[ pkgs.util-linux pkgs.coreutils_full pkgs.nettools ]";
        description = "List of derivations to put in wazuh-agent's path.";
      };

      config = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = ''
          Complete configuration for ossec.conf
        '';
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        description = ''
          Extra configuration values to be appended to the bottom of ossec.conf.
        '';
        default = "";
        example = ''
          <!-- The added ossec_config root tag is required -->
          <ossec_config>
            <!-- Extra configuration options as needed -->
          </ossec_config>
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          with cfg; (config == null) -> (extraConfig != null);
        message = "extraConfig cannot be set when config is set";
      }
    ];
    users.users.${wazuhUser} = {
      isSystemUser = true;
      group = wazuhGroup;
      description = "Wazuh agent user";
      home = stateDir;
      extraGroups = ["systemd-journal" "systemd-network"]; # To read journal entries
    };

    users.groups.${wazuhGroup} = {};

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${wazuhUser} ${wazuhGroup} 1d"
    ];

    systemd.targets.multi-user.wants = [ "wazuh.target" ];
    systemd.targets.wazuh.wants = forEach daemons (d: "${d}.service" );

    systemd.services =
      listToAttrs
        (map
          (daemon: nameValuePair daemon (mkService daemon))
          daemons) //
      { setup-pre-wazuh = {
         description = "Sets up wazuh's directory structure";
         wantedBy = map (d: "${d}.service") daemons;
         before = map (d: "${d}.service") daemons;
         serviceConfig = {
           Type = "oneshot";
           User = wazuhUser;
           Group = wazuhGroup;
           ExecStart =
             let
               script = pkgs.writeShellApplication { name = "wazuh-prestart"; text = preStart; };
             in "${script}/bin/wazuh-prestart";
         };
        };
      };

    security.wrappers =
      listToAttrs
        (forEach daemons
          (d:
            nameValuePair
              d
              {
                setgid = true;
                setuid = true;
                owner = wazuhUser;
                group = wazuhGroup;
                source = "${pkg}/bin/${d}";
              }
          )
        );
  };
}
