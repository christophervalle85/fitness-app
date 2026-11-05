# Weekform for iPhone

Open `Weekform.xcodeproj` in Xcode, select the **Weekform** scheme, and run on an iPhone or iPhone simulator with iOS 26.2 or later. This milestone lets you plan a training week offline.

## Set up a week

On first launch, choose **Build my routine** for a blank week or **Choose a starter** for an editable copy of **Three-day strength**. Name the routine, schedule workouts and rest days, and set the exercise order, working sets and rep or duration targets. Starting loads are optional. Review the week and tap **Save and use routine**.

**Today** shows the active routine’s prescription or rest day for the selected date. In **Routines**, you can edit, duplicate or archive a saved week, create another one, and choose which is active. SwiftData keeps the planner on the device. Reopening the app resumes an unfinished draft or returns to Today after confirmation.

## Local development

For an optional private starter, put a local JSON file matching the `WeekPlan` model in `DevelopmentPrivate/LocalStarter.json` and rebuild in Debug. Give it seven ordered days, starting with Monday. It appears under **Choose a starter**. Git ignores JSON files in that directory. The build copies the file into the Debug app when present and excludes it from Release. Keep Debug builds containing a private starter for personal testing.

Open **Developer tools** from the Debug welcome screen or either tab. **Replay onboarding** starts a new draft and keeps saved routines. **Reset planner test data** asks for confirmation before clearing the routines and draft for this installation. Use reset only with disposable test data. Release builds open the same weekly planner and omit the developer tools.

## Try the Lock Screen confirmation

Use a dedicated test iPhone with Live Activities enabled. The project has no signing team selected. Before installing on the phone, configure authorized signing for both `Weekform` and `WeekformActivity`. Their provisioning profiles must allow the same App Group, `group.com.christophervalle.weekform`.

1. In Debug, open **Developer tools → Foundation workout**. This separate one-set test uses eight synthetic reps. Check that **Status** reads **Ready**, tap **Start Live Activity**, then lock the phone.
2. On the Lock Screen, tap **Confirm 8 test reps**. Look for **Test set saved**. Unlock the phone and check that the app shows **Saved**. If Live Activities are disabled, you can exercise the in-app path with **Confirm 8 reps**.
3. Force-quit Weekform, reopen it, and go back to **Developer tools → Foundation workout**. **Status** should still read **Saved**, and the confirmation button should be gone. If storage is temporarily unavailable, unlock the phone and tap **Refresh saved result**.

The probe keeps one result across launches. To repeat from **Ready**, use a fresh dedicated simulator for the in-app check or a clean test installation with an empty Weekform App Group on a dedicated phone for the Lock Screen check. Keep resets confined to disposable test data.
