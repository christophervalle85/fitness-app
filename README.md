# Weekform for iPhone

Open `Weekform.xcodeproj` in Xcode, select the **Weekform** scheme, and run on an iPhone or iPhone simulator with iOS 26.2 or later. You can plan a week, log strength and cardio sessions offline, and see which scheduled work you have completed.

## Set up a week

On first launch, choose **Build my routine** for a blank week or **Choose a starter** for an editable copy of **Three-day strength**. Name the routine, schedule workouts and rest days, and set the exercise order, working sets and rep or duration targets. Starting loads are optional. Review the week and tap **Save and use routine**.

**Today** shows the active routine’s prescription or rest day for the selected date. In **Routines**, you can edit, duplicate or archive a saved week, create another one, and choose which is active. SwiftData keeps the planner on the device. Reopening the app resumes an unfinished draft or returns to Today after confirmation.

## Train

From **Today**, start the planned workout, an **Extra workout**, or **Cardio**. You can save several sessions on one day and resume one open workout at a time. To train ahead, select the scheduled date and tap **Do this workout today**. The plan keeps its scheduled date and the session records when you trained. To reschedule that one workout, use **Change schedule**.

In a strength session, check the actual reps, seconds or load shown for each set, then tap **Confirm set**. You can edit or undo a result, add an exercise, or swap the remaining sets while keeping the sets already logged. In-app rest controls let you pause or extend the interval. **Start set** ends rest. Finish a partial session and return to the planned workout later to complete its remaining work.

For repeating cardio, set a duration goal on the weekday in the routine editor. For a single date, use **Schedule a cardio activity** on Today. Set the goal in minutes. After training, enter the seconds you actually completed, add distance if desired, and tap **Confirm activity**. A shorter confirmed duration counts as partial. Additional confirmed sessions assigned to that same goal can complete it.

Extra workouts count toward a plan only when you assign them. Open the saved entry under **Sessions performed**, choose **Assign to planned work**, and select the date and a matching uncredited set or cardio goal. One confirmed set can fulfill one planned set.

## Setup follow-ups

The editor shows inline guidance when a routine needs a correction before review. Planned improvements include a calendar-style review of the full week and catalog suggestions that resolve exercise variants with fewer selections.

## Local development

For an optional private starter, put a local JSON file matching the `WeekPlan` model in `DevelopmentPrivate/LocalStarter.json` and rebuild in Debug. Give it seven ordered days, starting with Monday. It appears under **Choose a starter**. Git ignores JSON files in that directory. The build copies the file into the Debug app when present and excludes it from Release. Keep Debug builds containing a private starter for personal testing.

Open **Developer tools** from the Debug welcome screen or either tab. **Replay onboarding** starts a new draft and keeps saved routines. **Reset planner test data** asks for confirmation before clearing the routines and draft for this installation. Use reset only with disposable test data. Release builds open the same weekly planner and omit the developer tools.

## Try the development Lock Screen test

The current Live Activity exercises a single synthetic set. Use the in-app workout screen to log regular training sessions.

Use a dedicated test iPhone with Live Activities enabled. The project has no signing team selected. Before installing on the phone, configure authorized signing for both `Weekform` and `WeekformActivity`. Their provisioning profiles must allow the same App Group, `group.com.christophervalle.weekform`.

1. In Debug, open **Developer tools → Foundation workout**. This separate one-set test uses eight synthetic reps. Check that **Status** reads **Ready**, tap **Start Live Activity**, then lock the phone.
2. On the Lock Screen, tap **Confirm 8 test reps**. Look for **Test set saved**. Unlock the phone and check that the app shows **Saved**. If Live Activities are disabled, you can exercise the in-app path with **Confirm 8 reps**.
3. Force-quit Weekform, reopen it, and go back to **Developer tools → Foundation workout**. **Status** should still read **Saved**, and the confirmation button should be gone. If storage is temporarily unavailable, unlock the phone and tap **Refresh saved result**.

The probe keeps one result across launches. To repeat from **Ready**, use a fresh dedicated simulator for the in-app check or a clean test installation with an empty Weekform App Group on a dedicated phone for the Lock Screen check. Keep resets confined to disposable test data.
