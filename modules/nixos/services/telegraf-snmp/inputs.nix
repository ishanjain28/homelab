let
  ptp = {
    version = 2;
    community = "public";
    name = "ptp";
    field = [
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.1.0";
        name = "source";
        is_tag = true;
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.2.0";
        name = "model";
        is_tag = true;
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.3.0";
        name = "version";
        is_tag = true;
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.7.0";
        name = "mode";
        is_tag = true;
      }
      {
        oid = "SNMPv2-MIB::sysUpTime.0";
        name = "uptime";
        conversion = "float(2)";
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.8.0";
        name = "cpu_usage";
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.1.9.0";
        name = "memory_usage";
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.4.1.0";
        name = "snr";
      }
      {
        oid = "1.3.6.1.4.1.11863.20.1.4.2.0";
        name = "transmit_ccq";
      }
    ];
    table = [
      {
        oid = "IF-MIB::ifTable";
        name = "interface";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "IF-MIB::ifDescr";
            name = "ifDescr";
            is_tag = true;
          }
        ];
      }
    ];
  };
in
[
  (
    ptp
    // {
      agents = [ "udp://10.0.99.99:161" ];
      timeout = "2s";
      retries = 1;
    }
  )
  (
    ptp
    // {
      agents = [ "udp://10.0.99.100:161" ];
      timeout = "3s";
      retries = 1;
    }
  )
  {
    agents = [
      "udp://10.0.99.11:161"
      "udp://10.0.99.12:161"
    ];
    version = 3;
    sec_name = "public";
    sec_level = "noAuthNoPriv";
    timeout = "2s";
    retries = 1;
    name = "switch";
    field = [
      {
        oid = "SNMPv2-MIB::sysName.0";
        name = "source";
        is_tag = true;
      }
      {
        oid = "1.3.6.1.4.1.11863.6.1.1.5.0";
        name = "model";
        is_tag = true;
      }
      {
        oid = "1.3.6.1.4.1.11863.6.1.1.6.0";
        name = "version";
        is_tag = true;
      }
      {
        oid = "SNMPv2-MIB::sysUpTime.0";
        name = "uptime";
        conversion = "float(2)";
      }
    ];
    table = [
      {
        oid = "IF-MIB::ifTable";
        name = "interface";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "IF-MIB::ifDescr";
            name = "ifDescr";
            is_tag = true;
          }
        ];
      }
      {
        oid = "IF-MIB::ifXTable";
        name = "interface";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "IF-MIB::ifName";
            name = "ifName";
            is_tag = true;
          }
        ];
      }
    ];
  }
  {
    agents = [ "udp://10.0.50.1:161" ];
    version = 3;
    sec_name = "public";
    sec_level = "noAuthNoPriv";
    timeout = "2s";
    retries = 1;
    field = [
      {
        oid = "SNMPv2-MIB::sysName.0";
        name = "source";
        is_tag = true;
      }
      {
        oid = "SNMPv2-MIB::sysDescr.0";
        name = "model";
        is_tag = true;
      }
      {
        oid = "MIKROTIK-MIB::mtxrLicVersion.0";
        name = "version";
        is_tag = true;
      }
      {
        oid = "MIKROTIK-MIB::mtxrSerialNumber.0";
        name = "serial";
        is_tag = true;
      }
      {
        oid = "SNMPv2-MIB::sysUpTime.0";
        name = "uptime";
        conversion = "float(2)";
      }
      {
        oid = "MIKROTIK-MIB::mtxrHlProcessorTemperature.0";
        name = "cpu_temperature";
        conversion = "float(1)";
      }
    ];
    table = [
      {
        oid = "HOST-RESOURCES-MIB::hrProcessorTable";
        name = "cpu";
        index_as_tag = true;
        inherit_tags = [ "source" ];
      }
      {
        oid = "HOST-RESOURCES-MIB::hrStorageTable";
        name = "storage";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "HOST-RESOURCES-MIB::hrStorageDescr";
            name = "hrStorageDescr";
            is_tag = true;
          }
        ];
      }
      {
        oid = "MIKROTIK-MIB::mtxrGaugeTable";
        name = "health";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "MIKROTIK-MIB::mtxrGaugeName";
            name = "name";
            is_tag = true;
          }
        ];
      }
      {
        oid = "MIKROTIK-MIB::mtxrOpticalTable";
        name = "sfp";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "MIKROTIK-MIB::mtxrOpticalName";
            name = "name";
            is_tag = true;
          }
          {
            oid = "MIKROTIK-MIB::mtxrOpticalRxPower";
            name = "mtxrOpticalRxPower";
            conversion = "float(3)";
          }
          {
            oid = "MIKROTIK-MIB::mtxrOpticalTxPower";
            name = "mtxrOpticalTxPower";
            conversion = "float(3)";
          }
          {
            oid = "MIKROTIK-MIB::mtxrOpticalSupplyVoltage";
            name = "mtxrOpticalSupplyVoltage";
            conversion = "float(3)";
          }
          {
            oid = "MIKROTIK-MIB::mtxrOpticalWavelength";
            name = "mtxrOpticalWavelength";
            conversion = "float(2)";
          }
        ];
      }
      {
        oid = "IF-MIB::ifTable";
        name = "interface";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "IF-MIB::ifDescr";
            name = "ifDescr";
            is_tag = true;
          }
        ];
      }
      {
        oid = "IF-MIB::ifXTable";
        name = "interface";
        inherit_tags = [ "source" ];
        field = [
          {
            oid = "IF-MIB::ifName";
            name = "ifName";
            is_tag = true;
          }
        ];
      }
    ];
  }
]
