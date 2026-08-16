_: {
  mkVolume = volume: volume;

  mkMigratableVolume = volume: volume // { migratable = true; };
}
