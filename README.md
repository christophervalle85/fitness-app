# Weekform for iPhone

Open `Weekform.xcodeproj` in Xcode, select the **Weekform** scheme, and run on an iPhone or iPhone simulator with iOS 26.2 or later. Debug opens a one-set workout with eight synthetic reps. Release shows a Weekform placeholder.

## Try the Lock Screen confirmation

Use a dedicated test iPhone with Live Activities enabled. The project has no signing team selected. Before installing on the phone, configure authorized signing for both `Weekform` and `WeekformActivity`. Their provisioning profiles must allow the same App Group, `group.com.christophervalle.weekform`.

1. Open the Debug build and check that **Status** reads **Ready**. Tap **Start Live Activity**, then lock the phone.
2. On the Lock Screen, tap **Confirm 8 test reps**. Look for **Test set saved**. Unlock the phone and check that the app shows **Saved**. If Live Activities are disabled, you can exercise the in-app path with **Confirm 8 reps**.
3. Force-quit Weekform, then reopen it. **Status** should still read **Saved**, and the confirmation button should be gone. If storage is temporarily unavailable, unlock the phone and tap **Refresh saved result**.

The probe keeps one result across launches. To repeat from **Ready**, use a fresh dedicated simulator for the in-app check or a clean test installation with an empty Weekform App Group on a dedicated phone for the Lock Screen check. Keep resets confined to disposable test data.
