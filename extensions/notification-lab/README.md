# Notification Lab

Test Vehla’s brokered macOS notification support without doing unrelated work.

This extension demonstrates:

- A minimal immediate notification.
- A declarative form for a custom title, message, and delay.
- Asynchronous extension handlers.
- Foreground and background notification delivery.
- The `notifications` capability and its two permission layers.

## Install

Install **Notification Lab** from **Vehla Settings → Store**.

For local development:

```sh
npm --prefix extensions/notification-lab install --install-links
```

Then install `extensions/notification-lab` as a local package.

## Commands

### Send Test Notification

Keyword: `notifynow`

Returns a notification immediately. Use this command to test the Store capability prompt and the macOS authorization prompt.

### Send Delayed Notification

Keyword: `notifydelay`

Choose a 3, 5, or 10 second delay and enter a custom title and message. The command returns only a notification action—there is no result panel that can cover the banner.

The maximum delay is intentionally 10 seconds because Store commands have a 15-second execution limit.

## Test the complete permission flow

1. In **Settings → Store → Notification Lab**, set **Notifications** to **Ask**.
2. Run `notifydelay` from the palette.
3. Choose **5 seconds**, keep Vehla in the foreground, and submit the form.
4. When Vehla asks whether the extension may send notifications, choose **Allow Once** or **Always Allow**.
5. If macOS has never asked before, approve its system notification prompt.
6. The banner should arrive after Vehla queues it for delivery.

If macOS permission was denied previously, it will not display its one-time prompt again. Vehla will offer to open **System Settings → Notifications** instead. Enable notifications for Vehla there, then rerun the command.

To test foreground presentation, leave Vehla active while waiting. To test background presentation, switch to another application after submitting the form.

## Permission model

Notification delivery requires both:

1. The package-level `notifications` capability decision in Vehla.
2. macOS notification authorization for the Vehla application.

Changing one layer does not modify the other. An extension can only request a brokered action; Vehla owns authorization and delivery.
