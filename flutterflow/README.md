# Hibira for FlutterFlow

Realtime events and live presence in [FlutterFlow](https://flutterflow.io) apps,
with [Hibira](https://hibira.io) Channels. This folder holds the custom actions
and widgets of the **Hibira Realtime** FlutterFlow library. They wrap the
[`hibira`](https://pub.dev/packages/hibira) package from this repo.

The files under `lib/custom_code/` are the exact code that goes into
FlutterFlow. The rest of `lib/` stands in for the files FlutterFlow generates,
so CI can analyze and test that code.

## What you get

| Kind | Name | What it does |
|---|---|---|
| Action | `hibiraConnect` | Connects once, for example on the first page's load. |
| Action | `hibiraSubscribe` | Runs an action each time an event arrives, across pages. |
| Action | `hibiraUnsubscribe` | Stops the listeners `hibiraSubscribe` started. |
| Action | `hibiraTrigger` | Sends a client event (typing, cursors) on a private or presence channel. |
| Action | `hibiraPresenceMembers` | Lists who is on a presence channel, as JSON. |
| Action | `hibiraDisconnect` | Closes the connection, for example on sign-out. |
| Widget | `HibiraEventListener` | Runs an action for each event while the page is open. Draws nothing. |
| Widget | `HibiraPresenceCount` | Live "12 online" counter for a presence channel. |
| Widget | `HibiraConnectionStatus` | Green, amber or red dot for the connection. |

## Using the library in your FlutterFlow project

1. Create a free app at [hibira.io](https://hibira.io) and copy its app key.
2. In FlutterFlow, open **Settings and Integrations > Project Dependencies**,
   add **Hibira Realtime**, and fill in the library values:
   - `hibiraAppKey`: your app key (public, safe in the app). Never put the app
     secret in a FlutterFlow project.
   - `hibiraHost`: leave it as `ws.hibira.io`.
   - `hibiraAuthEndpoint`: only for private and presence channels, the URL
     on your backend that signs subscriptions (any Pusher server SDK does it).
3. On your first page, add the action **Hibira Connect** to **On Page Load**.
4. Drop a `HibiraEventListener` on a page, set the channel (`orders`) and
   event (`shipped`), and pick the action to run in **On Event**, such as
   updating page state with the event data.
5. Publish an event from your backend with any Pusher server SDK pointed at
   Hibira, or from the debug console in the Hibira portal.

For presence channels, sign in your users first and pass their token as
`authToken` to `hibiraConnect`; it is sent to your auth endpoint as
`Authorization: Bearer <token>`.

## Building the library in FlutterFlow (maintainers)

FlutterFlow libraries are built in the FlutterFlow editor; there is no import
from Git. Publishing needs a paid FlutterFlow plan (Basic or above), because
the Free plan can't add pub.dev packages or publish libraries.

1. Create a new blank project named **Hibira Realtime** (no Firebase, no
   Supabase). Clone it first if you want a copy that stays a normal project:
   publishing as a library can't be undone.
2. **Custom Code > Pubspec Dependencies**: add `hibira: ^0.1.1`.
3. Add each custom action under **Custom Code > + Add > Action** with the
   name, arguments and return type below. Paste the file's code over
   everything below `// DO NOT REMOVE OR MODIFY THE CODE ABOVE!`, then
   **Save** and **Compile**. Add `hibiraConnect` first: the other files import
   it.

   | Action | Arguments (FlutterFlow type, nullable?) | Return |
   |---|---|---|
   | `hibiraConnect` | `appKey` String; `host` String, nullable; `authEndpoint` String, nullable; `authToken` String, nullable | Boolean |
   | `hibiraDisconnect` | none | none |
   | `hibiraSubscribe` | `channelName` String; `eventName` String, nullable; `onEvent` Action (Parameters: `data` JSON) | none |
   | `hibiraUnsubscribe` | `channelName` String | none |
   | `hibiraTrigger` | `channelName` String; `eventName` String; `data` JSON | Boolean |
   | `hibiraPresenceMembers` | `channelName` String | JSON, list |

4. Add each widget under **Custom Code > + Add > Widget** the same way:

   | Widget | Parameters (FlutterFlow type, nullable?) |
   |---|---|
   | `HibiraEventListener` | `channelName` String; `eventName` String, nullable; `onEvent` Action (Parameters: `data` JSON) |
   | `HibiraPresenceCount` | `channelName` String; `label` String, nullable; `textColor` Color, nullable; `dotColor` Color, nullable; `fontSize` Double, nullable; `onChanged` Action, nullable (Parameters: `members` JSON, list) |
   | `HibiraConnectionStatus` | `showText` Boolean, nullable; `connectedText` String, nullable; `connectingText` String, nullable; `offlineText` String, nullable; `fontSize` Double, nullable |

5. **Settings and Integrations > App Settings > Publish as Library > Library
   Values**: add `hibiraAppKey` (String), `hibiraHost` (String, default
   `ws.hibira.io`) and `hibiraAuthEndpoint` (String, nullable).
6. **Action Blocks**: add an app-level block **Hibira Connect** that calls
   `hibiraConnect` with the three library values (and an optional `authToken`
   parameter), so users don't wire the values themselves.
7. Add a demo page: a `HibiraConnectionStatus`, a `HibiraPresenceCount` on
   `presence-demo` and a list fed by a `HibiraEventListener`. Test it in Run
   Mode against the shared demo app.
8. Commit on `main`, then **Publish as Library** with the message
   "Hibira Realtime 0.1.0".
9. Marketplace: **Share icon > Create New Item > Set For Marketplace**, item
   type **Library**, price free, platforms Android, iOS and Web. Use the
   listing text below and a 1200 x 800 cover without the FlutterFlow logo.
   Review takes up to 30 days.

When the code here changes, paste the changed file into FlutterFlow and
publish a new library version.

## Marketplace listing

**Name:** Hibira Realtime: Live Events and Presence

**Description:**

Add realtime updates to your FlutterFlow app without running a WebSocket
server. Hibira Realtime connects your app to Hibira Channels, a hosted
service that speaks the Pusher protocol, so any Pusher server SDK (Node,
PHP/Laravel, Python, Go, Ruby) can push events to your screens.

- Live events: run any action when an order ships, a message arrives or a
  dashboard number changes.
- Presence: show who is online with a live "12 online" counter and the member
  list.
- Client events: typing indicators and cursor moves between users.
- Connection status dot for chat and dashboard screens.
- Works on Android, iOS and the web. Reconnects by itself.

Needs a Hibira account (free plan, no card) and uses the open-source
[`hibira`](https://pub.dev/packages/hibira) package from pub.dev (MIT).

**Usage instructions:** steps 1 to 5 of "Using the library" above.

**Documentation URL:** https://github.com/hibira-io/flutter/tree/main/flutterflow

## 中文摘要

這個資料夾是 FlutterFlow 函式庫「Hibira Realtime」的程式碼:6 個 custom action
(連線、訂閱、取消訂閱、client event、presence 成員、斷線)和 3 個 widget
(事件監聽、線上人數、連線狀態)。`lib/custom_code/` 底下就是要貼進 FlutterFlow 的
程式碼,其餘檔案只是讓 CI 能檢查用的替身。FlutterFlow 函式庫只能在編輯器裡建立和
發布,需要 Basic 以上的付費方案;步驟見「Building the library in FlutterFlow」。
