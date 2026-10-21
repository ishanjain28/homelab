_: {
  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      NSAutomaticCapitalizationEnabled = true;
      NSAutomaticDashSubstitutionEnabled = true;
      NSAutomaticPeriodSubstitutionEnabled = true;
      NSAutomaticQuoteSubstitutionEnabled = true;
    };

    finder = {
      AppleShowAllFiles = true;
      FXDefaultSearchScope = "SCcf";
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv";
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowMountedServersOnDesktop = true;
      ShowPathbar = true;
      ShowRemovableMediaOnDesktop = true;
      ShowStatusBar = true;
      _FXSortFoldersFirst = true;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
    };

    screencapture.show-thumbnail = false;
  };
}
