## 0.2.0

- Uses hibira-push-android 1.3.0 and hibira-push-ios 1.3.0, whose default
  endpoint is `https://api.hibira.io`, Hibira's API host.
  `https://ws.hibira.io` keeps working, so existing apps need no change.
- Android depends on the push library only (`push-android`), not the whole
  hibira-push-android repository, so apps no longer pull in its chat module.

## 0.1.1

- README: cover image and screenshots.

## 0.1.0

- First release: Flutter plugin for Hibira Push on Android (hibira-push-android
  1.1.0, FCM) and iOS (hibira-push-ios 1.1.0, APNs) with device interests,
  authenticated users, foreground and opened messages.
