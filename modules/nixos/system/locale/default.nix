{ lib, ... }: {
  console.keyMap = lib.mkForce "us";
  i18n.defaultLocale = "en_IN";
}
