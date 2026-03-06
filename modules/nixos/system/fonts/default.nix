{ pkgs, ... }: {
  fonts = {
    packages = with pkgs; [
      cabin
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      unifont
    ];
  };
}
