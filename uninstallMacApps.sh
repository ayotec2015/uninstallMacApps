#!/bin/bash
################################################################################
# @Author: Alexander Duffner
# @Date:   2023-02-06T21:52:52+01:00
# @Filename: uninstallMacApps.sh
# @Last modified by:   Alexander Duffner
# @Last modified time: 2023-02-09T13:56:14+01:00
################################################################################
# CREDITS: Heavily inspired of [1] and [2] - all Kudos to them!
# [1] https://github.com/sunknudsen/privacy-guides/blob/dc98eaf2f4fe1a384b94c80d4c8b37c6839618d5/how-to-clean-uninstall-macos-apps-using-appcleaner-open-source-alternative/app-cleaner.sh
# [2] https://community.jamf.com/t5/jamf-pro/delete-applications-without-adminrights-withs-self-service/m-p/195829
# Additionally I implemented: https://github.com/bartreardon/swiftDialog
################################################################################

safeMode="false" # true means only nothing will be deleted

# Some apps we may don't want let the user to uninstall trough this way
blacklistNames="Jamf Connect
Microsoft Defender
TeamViewer QuickSupport
Privileges
Self Service
Support"

# Some apps we may don't want let the user to uninstall trough this way
blacklistBundlePrefixes="com.apple
com.adobe
com.cisco
com.jamf
corp.sap.privileges"

# Function for let user choose an app
askForApp() {
  /usr/bin/osascript - <<EOF 2>/dev/null
    set strPath to POSIX file "/Applications/"
    set f to (choose file with prompt "$1" default location strPath)
    set posixF to POSIX path of f
    posixF
EOF
}

# User will be aske d to choose an app
app=$(askForApp 'Please select the app you want to delete') || exit

if [ ! -e "$app/Contents/Info.plist" ]; then
  echo "Cannot find app plist"
  exit 1
fi

currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3}')
trash() { mv "$@" /Users/$currentUser/.Trash/ ; }
bundle_identifier=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null)
app_name=$(basename "$app" .app)

if [ "$bundle_identifier" = "" ]; then
  echo "Cannot find app bundle identifier"
  exit 1
fi

# We will stop it, if the app should be not allowed to be uninstalled
if (grep -q "$app_name" <<<$blacklistNames || grep -q "$blacklistBundlePrefixes" <<<$bundle_identifier); then
  /usr/local/bin/dialog --title "$app_name" --icon "${app/%?/}" \
    --message "This app cannot be uninstalled as it is an integral part of the operating system or required by internal IT.

This means that the app is necessary for the proper functioning of your device and removing it could cause unforeseen issues.

Thank you for your understanding." \
    --button1text "Okay"
  exit 0
fi

sleep 1

echo "Checking for running processes …"
################################# DO NOT TOUCH #################################
processes=($(pgrep -afil "$app_name" | grep -v "uninstallMacApps.sh"))
################################# DO NOT TOUCH #################################

IFS=$'\n'

if [ ${#processes[@]} -gt 0 ]; then

  /usr/local/bin/dialog --title "Stop $app_name" --icon "${app/%?/}" \
    --message "By clicking \"Stop the app\" the app will be closed and any unsaved changes may be lost.

We strongly advise you to save any important information before closing the app.

Please note that once the app is closed, any unsaved changes will be permanently lost and cannot be recovered." \
    --button1text "Stop the app" --button2text "Cancel" \
    --overlayicon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"

  answer=$?
  if [ "$answer" = "0" ]; then
    echo "Killing running processes …"
    # TODO - maybe find a smoother way to kill, without blinking CrashReporter
    ################################# DO NOT TOUCH #################################
    killall "$app_name"
    ################################# DO NOT TOUCH #################################
    sleep 3
  elif [ "$answer" = "2" ]; then
    exit 0
  fi
fi

################################# DO NOT TOUCH #################################
paths=()

paths+=($(find /private/var/db/receipts -iname "*$app_name*.bom" -maxdepth 1 -prune 2>&1 | grep -v "Permission denied"))
paths+=($(find /private/var/db/receipts -iname "*$bundle_identifier*.bom" -maxdepth 1 -prune 2>&1 | grep -v "Permission denied"))
################################# DO NOT TOUCH #################################

echo "Finding app data …"

locations=(
  "/Users/$currentUser/Library"
  "/Users/$currentUser/Library/Application Scripts"
  "/Users/$currentUser/Library/Application Support"
  "/Users/$currentUser/Library/Application Support/CrashReporter"
  "/Users/$currentUser/Library/Containers"
  "/Users/$currentUser/Library/Caches"
  "/Users/$currentUser/Library/HTTPStorages"
  "/Users/$currentUser/Library/Group Containers"
  "/Users/$currentUser/Library/Internet Plug-Ins"
  "/Users/$currentUser/Library/LaunchAgents"
  "/Users/$currentUser/Library/Logs"
  "/Users/$currentUser/Library/Preferences"
  "/Users/$currentUser/Library/Preferences/ByHost"
  "/Users/$currentUser/Library/Saved Application State"
  "/Users/$currentUser/Library/WebKit"
  "/Library"
  "/Library/Application Support"
  "/Library/Application Support/CrashReporter"
  "/Library/Caches"
  "/Library/Extensions"
  "/Library/Internet Plug-Ins"
  "/Library/LaunchAgents"
  "/Library/LaunchDaemons"
  "/Library/Logs"
  "/Library/Preferences"
  "/Library/PrivilegedHelperTools"
  "/private/var/db/receipts"
  "/usr/local/bin"
  "/usr/local/etc"
  "/usr/local/opt"
  "/usr/local/sbin"
  "/usr/local/share"
  "/usr/local/var"
  "$(/usr/bin/sudo -u "$currentUser" getconf DARWIN_USER_CACHE_DIR | sed "s/\/$//")"
  "$(/usr/bin/sudo -u "$currentUser" getconf DARWIN_USER_TEMP_DIR | sed "s/\/$//")"
)

################################# DO NOT TOUCH #################################
paths=($app)

for location in "${locations[@]}"; do
  paths+=($(find "$location" -iname "*$app_name*" -maxdepth 1 -prune 2>&1 | grep -v "No such file or directory" | grep -v "Operation not permitted" | grep -v "Permission denied"))
done

for location in "${locations[@]}"; do
  paths+=($(find "$location" -iname "*$bundle_identifier*" -maxdepth 1 -prune 2>&1 | grep -v "No such file or directory" | grep -v "Operation not permitted" | grep -v "Permission denied"))
done

paths=($(printf "%s\n" "${paths[@]}" | sort -u))
################################# DO NOT TOUCH #################################

/usr/local/bin/dialog --title "Uninstall $app_name" --icon "${app/%?/}" \
  --messagefont "size=13" --message "## Move following app data to trash?\n\n
$(for i in "${paths[@]}"; do echo -e "- $i"; done)" \
  --button1text "Delete" --button2text "Cancel" \
  --overlayicon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FullTrashIcon.icns"

answer=$?
if [[ $safeMode == false ]]; then
  answer="$answer"
else
  answer="2"
  echo "Nothing deleted. Safe Mode was on."
fi

if [ "$answer" = "0" ]; then
  echo "Moving app data to trash…"
  sleep 1
  ################################ DO NOT TOUCH ################################
  posixFiles=$(printf ", POSIX file \"%s\"" ${paths[@]} | awk '{print substr($0,3)}')
  ################################ DO NOT TOUCH ################################
 # echo "$posixFiles"
 for appsToDel in ${paths[@]}; do
   echo "Deleting ${appsToDel}"
   rm -rf "$appsToDel"
 done
  #/usr/bin/sudo -u "$currentUser" osascript -e "tell application \"Finder\" to delete { $posixFiles }" >/dev/null
  #echo "Done"
elif [ "$answer" = "2" ]; then
  exit 0
fi
