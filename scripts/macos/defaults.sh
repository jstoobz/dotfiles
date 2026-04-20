#!/usr/bin/env bash
# ============================================================================
# macOS defaults — UI/UX, input, Finder, Dock, Activity Monitor, crash reporter
#
# Safe to re-run. Each setting is guarded by apply_default which tolerates
# failures (macOS version drift, domain changes) and bumps counters.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/utils.sh
. "${SCRIPT_DIR}/../../lib/utils.sh"

DEFAULTS_APPLIED=0
DEFAULTS_FAILED=0

main() {
  step "macOS Defaults"

  # Close System Preferences/Settings so they don't clobber our writes.
  osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true
  osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true

  # ==========================================================================
  step "General UI/UX"
  # ==========================================================================

  apply_sudo_default "Disable boot sound" write /Library/Preferences/SystemConfiguration/com.apple.Boot.plist SystemAudioVolume " "
  apply_default "Sidebar icon size" write NSGlobalDomain NSTableViewDefaultSizeMode -int 2
  apply_default "Always show scrollbars" write NSGlobalDomain AppleShowScrollBars -string "Always"
  apply_default "Disable focus ring animation" write NSGlobalDomain NSUseAnimatedFocusRing -bool false
  apply_default "Toolbar title rollover delay" write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0
  apply_default "Window resize speed" write NSGlobalDomain NSWindowResizeTime -float 0.001
  apply_default "Expand save panel" write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  apply_default "Expand save panel v2" write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  apply_default "Expand print panel" write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  apply_default "Expand print panel v2" write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
  apply_default "Save to disk (not iCloud) by default" write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
  apply_default "Auto-quit printer app when jobs finish" write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

  # LSQuarantine disables the "Are you sure you want to open this app downloaded
  # from the internet?" prompt. Kept off for dev-box ergonomics (you download
  # unsigned binaries often). Tradeoff: one fewer speed-bump against a spoofed
  # dmg. Flip to `true` if you want the prompt back.
  apply_default "Disable downloaded-app confirmation" write com.apple.LaunchServices LSQuarantine -bool false

  apply_default "Disable Resume system-wide" write com.apple.systempreferences NSQuitAlwaysKeepsWindows -bool false
  apply_default "Disable auto-termination of idle apps" write NSGlobalDomain NSDisableAutomaticTermination -bool true
  apply_default "Disable auto-capitalization" write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  apply_default "Disable smart dashes" write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  apply_default "Disable auto period substitution" write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  apply_default "Disable smart quotes" write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  apply_default "Disable auto-correct" write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

  # ==========================================================================
  step "Input devices"
  # ==========================================================================

  apply_default "Trackpad tap-to-click (bluetooth)" write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  apply_default "Trackpad tap-to-click (current host)" -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  apply_default "Trackpad tap-to-click (global)" write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
  apply_default "Three-finger drag (internal)" write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
  apply_default "Three-finger drag (bluetooth)" write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
  apply_default "Full keyboard access for all controls" write NSGlobalDomain AppleKeyboardUIMode -int 3
  apply_default "Disable press-and-hold (for Vim key repeat)" write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  apply_default "Fast key repeat rate" write NSGlobalDomain KeyRepeat -int 2
  apply_default "Short key repeat delay" write NSGlobalDomain InitialKeyRepeat -int 15
  apply_default "Language" write NSGlobalDomain AppleLanguages -array "en-US"
  apply_default "Locale" write NSGlobalDomain AppleLocale -string "en_US@currency=USD"
  apply_default "Measurement units" write NSGlobalDomain AppleMeasurementUnits -string "Inches"
  apply_default "Metric off" write NSGlobalDomain AppleMetricUnits -bool false

  # ==========================================================================
  step "Energy"
  # ==========================================================================

  apply_sudo_default "Lid wakeup" pmset -a lidwake 1
  apply_sudo_default "Auto-restart on power loss" pmset -a autorestart 1
  apply_sudo_default "Display sleep on battery (5 min)" pmset -b displaysleep 5
  apply_sudo_default "Display sleep on power (10 min)" pmset -c displaysleep 10
  apply_sudo_default "Machine sleep on battery (15 min)" pmset -b sleep 15
  apply_sudo_default "Machine sleep on power (never)" pmset -c sleep 0

  # ==========================================================================
  step "Screen & screenshots"
  # ==========================================================================

  apply_default "Require password after sleep" write com.apple.screensaver askForPassword -int 1
  apply_default "Password required immediately" write com.apple.screensaver askForPasswordDelay -int 0

  # Ensure the screenshot directory exists before pointing the system at it.
  mkdir -p "${HOME}/screenshots"
  apply_default "Screenshot location ~/screenshots" write com.apple.screencapture location -string "${HOME}/screenshots"
  apply_default "Screenshot PNG" write com.apple.screencapture type -string "png"
  apply_default "Screenshot no drop-shadow" write com.apple.screencapture disable-shadow -bool true
  apply_default "Subpixel font smoothing on non-Apple LCDs" -currentHost write -g AppleFontSmoothing -int 1
  apply_sudo_default "HiDPI display modes" write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  # ==========================================================================
  step "Finder"
  # ==========================================================================

  apply_default "Allow quit via ⌘Q" write com.apple.finder QuitMenuItem -bool true
  apply_default "Disable Get Info animation" write com.apple.finder DisableAllAnimations -bool true
  apply_default "New windows open in home" write com.apple.finder NewWindowTarget -string "PfHm"
  apply_default "New window path = \$HOME" write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
  apply_default "Show hard drives on desktop" write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  apply_default "Show servers on desktop" write com.apple.finder ShowMountedServersOnDesktop -bool true
  apply_default "Show removable media on desktop" write com.apple.finder ShowRemovableMediaOnDesktop -bool true
  apply_default "Show all file extensions" write NSGlobalDomain AppleShowAllExtensions -bool true
  apply_default "Finder status bar" write com.apple.finder ShowStatusBar -bool true
  apply_default "Finder path bar" write com.apple.finder ShowPathbar -bool true
  apply_default "Full POSIX path in Finder title" write com.apple.finder _FXShowPosixPathInTitle -bool true
  apply_default "Folders first when sorting by name" write com.apple.finder _FXSortFoldersFirst -bool true
  apply_default "Search the current folder by default" write com.apple.finder FXDefaultSearchScope -string "SCcf"
  apply_default "No file-extension change warning" write com.apple.finder FXEnableExtensionChangeWarning -bool false
  apply_default "Spring loading" write NSGlobalDomain com.apple.springing.enabled -bool true
  apply_default "Spring loading delay 0" write NSGlobalDomain com.apple.springing.delay -float 0
  apply_default "No .DS_Store on network volumes" write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  apply_default "No .DS_Store on USB volumes" write com.apple.desktopservices DSDontWriteUSBStores -bool true
  apply_default "Skip dmg verification" write com.apple.frameworks.diskimages skip-verify -bool true
  apply_default "Skip dmg verification (locked)" write com.apple.frameworks.diskimages skip-verify-locked -bool true
  apply_default "Skip dmg verification (remote)" write com.apple.frameworks.diskimages skip-verify-remote -bool true
  apply_default "Auto-open RO volume on mount" write com.apple.frameworks.diskimages auto-open-ro-root -bool true
  apply_default "Auto-open RW volume on mount" write com.apple.frameworks.diskimages auto-open-rw-root -bool true
  apply_default "Open Finder window on new disk" write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  apply_default "Default Finder view = List" write com.apple.finder FXPreferredViewStyle -string "Nlsv"
  apply_default "No trash warning" write com.apple.finder WarnOnEmptyTrash -bool false
  apply_default "Hide desktop icons" write com.apple.finder CreateDesktop -bool false
  apply_default "Expand Get Info panes" write com.apple.finder FXInfoPanesExpanded -dict General -bool true OpenWith -bool true Privileges -bool true

  chflags nohidden "${HOME}/Library" 2>/dev/null || warn "Could not unhide ~/Library"
  sudo chflags nohidden /Volumes 2>/dev/null || warn "Could not unhide /Volumes"

  # ==========================================================================
  step "Dock & Mission Control"
  # ==========================================================================

  apply_default "Dock tile size 48" write com.apple.dock tilesize -int 48
  apply_default "Minimize effect = scale" write com.apple.dock mineffect -string "scale"
  apply_default "Minimize to app icon" write com.apple.dock minimize-to-application -bool true
  apply_default "Dock spring loading" write com.apple.dock enable-spring-load-actions-on-all-items -bool true
  apply_default "Process indicator dots" write com.apple.dock show-process-indicators -bool true
  apply_default "No app-launch animation" write com.apple.dock launchanim -bool false
  apply_default "Faster Mission Control animation" write com.apple.dock expose-animation-duration -float 0.1
  apply_default "Don't group windows by app in MC" write com.apple.dock expose-group-by-app -bool false
  apply_default "Disable Dashboard" write com.apple.dashboard mcx-disabled -bool true
  apply_default "No Dashboard as a Space" write com.apple.dock dashboard-in-overlay -bool true
  apply_default "Don't rearrange Spaces by recency" write com.apple.dock mru-spaces -bool false
  apply_default "Dock show delay = 0" write com.apple.dock autohide-delay -float 0
  apply_default "Dock animation speed = 0" write com.apple.dock autohide-time-modifier -float 0
  apply_default "Dock auto-hide" write com.apple.dock autohide -bool true
  apply_default "Hidden app icons translucent" write com.apple.dock showhidden -bool true
  apply_default "No recent apps in Dock" write com.apple.dock show-recents -bool false

  # Hot corners. Values: 2=Mission Control, 4=Desktop, 5=Start screensaver,
  # 10=Display sleep, 11=Launchpad, 13=Lock Screen, 14=Quick Note.
  apply_default "Hot corner TL = Mission Control" write com.apple.dock wvous-tl-corner -int 2
  apply_default "Hot corner TL modifier" write com.apple.dock wvous-tl-modifier -int 0
  apply_default "Hot corner TR = Desktop" write com.apple.dock wvous-tr-corner -int 4
  apply_default "Hot corner TR modifier" write com.apple.dock wvous-tr-modifier -int 0
  apply_default "Hot corner BL = Screensaver" write com.apple.dock wvous-bl-corner -int 5
  apply_default "Hot corner BL modifier" write com.apple.dock wvous-bl-modifier -int 0
  apply_default "Hot corner BR = Lock Screen" write com.apple.dock wvous-br-corner -int 13
  apply_default "Hot corner BR modifier" write com.apple.dock wvous-br-modifier -int 0

  # ==========================================================================
  step "Time Machine"
  # ==========================================================================

  apply_default "Don't prompt for new Time Machine disks" write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  # ==========================================================================
  step "Activity Monitor"
  # ==========================================================================

  apply_default "Show main window on launch" write com.apple.ActivityMonitor OpenMainWindow -bool true
  apply_default "CPU usage in Dock icon" write com.apple.ActivityMonitor IconType -int 5
  apply_default "Show all processes" write com.apple.ActivityMonitor ShowCategory -int 0
  apply_default "Sort by CPU usage" write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
  apply_default "Sort descending" write com.apple.ActivityMonitor SortDirection -int 0

  # ==========================================================================
  step "Utilities"
  # ==========================================================================

  apply_default "Contacts debug menu" write com.apple.addressbook ABShowDebugMenu -bool true
  apply_default "TextEdit plain text" write com.apple.TextEdit RichText -int 0
  apply_default "TextEdit UTF-8 open" write com.apple.TextEdit PlainTextEncoding -int 4
  apply_default "TextEdit UTF-8 save" write com.apple.TextEdit PlainTextEncodingForWrite -int 4
  apply_default "Disk Utility debug menu" write com.apple.DiskUtility DUDebugMenuEnabled -bool true
  apply_default "Disk Utility advanced image opts" write com.apple.DiskUtility advanced-image-options -bool true

  # ==========================================================================
  step "Software updates"
  # ==========================================================================

  apply_default "Auto-check for updates" write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  apply_default "Check daily" write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  apply_default "Download updates in background" write com.apple.SoftwareUpdate AutomaticDownload -int 1
  apply_default "Install security updates" write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
  apply_default "App Store auto-update" write com.apple.commerce AutoUpdate -bool true

  # ==========================================================================
  step "Photos & Messages"
  # ==========================================================================

  apply_default "Don't auto-open Photos on plug-in" -currentHost write com.apple.ImageCapture disableHotPlug -bool true
  apply_default "Messages: no auto-emoji" write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false
  apply_default "Messages: no smart quotes" write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false
  apply_default "Messages: no spell check" write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false

  # ==========================================================================
  step "Crash reporter"
  # ==========================================================================

  # Silence the "application quit unexpectedly" dialog; crashes still log to
  # ~/Library/Logs/DiagnosticReports/ — just no popup.
  apply_default "No crash reporter dialog" write com.apple.CrashReporter DialogType -string "none"

  # Opt out of sending diagnostic data to Apple and third-party devs.
  apply_sudo_default "Diagnostics: don't submit to Apple" write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist AutoSubmit -bool false
  apply_sudo_default "Diagnostics: don't submit to 3rd parties" write /Library/Application\ Support/CrashReporter/DiagnosticMessagesHistory.plist ThirdPartyDataSubmit -bool false

  # ==========================================================================
  step "Restart affected applications"
  # ==========================================================================

  # Restart cfprefsd first so our writes land even for apps that cache
  # preferences aggressively. Explicitly excluded: Terminal (would kill us).
  local apps=(
    cfprefsd
    "Activity Monitor"
    "Address Book"
    Contacts
    Dock
    Finder
    Messages
    Photos
    SystemUIServer
  )

  for app in "${apps[@]}"; do
    killall "$app" 2>/dev/null || true
  done

  echo ""
  success "macOS defaults applied: ${DEFAULTS_APPLIED}  skipped: ${DEFAULTS_FAILED}"
  info "Some settings require logout/restart to fully take effect."
}

main "$@"
