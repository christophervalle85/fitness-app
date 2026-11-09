# Weekform for iPhone

Open `Weekform.xcodeproj` in Xcode, select the **Weekform** scheme, and run on an iPhone or iPhone simulator with iOS 26.2 or later. You can plan a week, log strength and cardio sessions offline, and see which scheduled work you have completed.

## Set up a week

On first launch, choose **Build my routine** for a blank week or **Choose a starter** for an editable copy of **Three-day strength**. Name the routine, schedule workouts and rest days, and set the exercise order, working sets and rep or duration targets. Starting loads are optional.

In the exercise editor, **Choose from exercise library** lets you select a specific variant and its recording method. Check the targets after switching between reps and duration. For unresolved starter choices, open **Review library matches** to preview exact catalog matches by weekday. Tap **Use these choices** to apply the displayed suggestions. Choose any remaining equipment or grip variants individually, or enter a custom exercise. The editor shows which choices still need attention. In **Review your week**, tap each weekday to check its prescription, cardio goal or rest day before choosing **Save and use routine**.

**Plan** shows the workout or rest day for the selected date. Tap the month and year to choose a date from the calendar. Swipe left or right across the week to page between weeks while keeping the same weekday selected. VoiceOver actions on that title offer previous week, next week and return to today. Paging follows the gesture, and selected-day content settles gently. Reduce Motion disables the content fade. A small diamond above the date marks today. The week uses a dumbbell for scheduled work, a dash for a rest day and a checkmark when all planned work for the date is fulfilled.

In **Routines**, open a saved routine’s three-dot card menu for **Edit**, **Make active**, **Duplicate**, **Archive** or **Delete**, as applicable. Archived routines offer **Duplicate** and **Delete**. Confirming **Delete routine** permanently removes the routine and its repeating schedule while keeping logged workouts and date-specific schedule entries. Deleting the active routine leaves Plan without an active routine until you choose one. Tap **New routine**, then **Start from scratch** or **Use a preset**. Additional routines save without changing your active routine by default; turn on **Use as my active routine** during review to activate the new routine when saving. Saving returns you to Routines. SwiftData keeps the planner on the device, and reopening the app resumes an unfinished draft.

## Train

From **Plan**, use **Start** to open a workout, **Resume** to return to an open session or **Continue** to pick up the remaining work after a partial session. Its status shows your progress. Starting a workout scheduled for another date keeps its planned date and records when you actually trained. The card’s ellipsis menu offers **Reschedule**, **Skip** or **Remove** when eligible. To move a workout, choose **Reschedule**, select a date and tap **Move workout**. Moving or confirming a skip affects only that scheduled workout and preserves the routine and saved results. Confirming **Remove** for added scheduled cardio removes its plan entry while keeping saved sessions in history on their original dates. **Extra workout** and **Log cardio** directly start unscheduled sessions.

You can keep several workouts open at once. Starting or resuming a different workout opens it immediately and keeps the others available with their progress saved. Resume scheduled sessions from their workout cards and unscheduled sessions from **Open unscheduled workouts** in Plan. The **Resume** bar can also take you back to the last workout you opened.

The training week closes when Monday begins in your local time. You can catch up on missed workouts within the week. At rollover, Weekform saves confirmed work in history and marks unfinished sessions partial. It keeps drafts with saved edits in history and clears untouched attempts. Past weeks are read-only in Plan. You can still correct saved results in workout history.

**Workout progress** shows logged and remaining sets by exercise. Expand an exercise to see its sets, then tap a set name to open its inline editor. Enter reps, seconds or load with the keyboard or adjust the values with plus and minus. Weekform may suggest the last comparable set; review the values and tap **Confirm set** to save them. Logged sets show their values. Tap a logged set name to correct it, then tap again to close the editor. Undo a saved result from workout history. To remove an unlogged set or warm-up that you added, swipe left on its row and tap **Remove**. Press and hold an exercise heading for **Instructions** or, when available, **What to track**. Each expanded exercise card has **Add set** options for **Working set** and **Warm-up**, plus **Swap** for remaining sets. The bottom **Add exercise** and **Rest** tools remain available. **Start set** ends the rest interval.

Tap **Finish** to open the workout summary and add an optional note. You can save a partial session and continue the planned workout later. **Close** keeps the session open so you can resume it. Its checklist shows sets completed earlier alongside the remaining work. On finish, Weekform returns to Plan and selects the planned date for a linked workout or the performed date for an extra session. The calendar shows a checkmark when all workouts planned for that date are fulfilled. Reduce Motion turns off the completion bounce.

For repeating cardio, set a duration goal on the weekday in the routine editor. For a single date, tap **Add cardio** on Plan. Choose **Walking**, **Running**, **Cycling** or **Custom**, then set the duration in minutes and the date. Tap **Schedule activity** to add it to the plan. After training, enter the seconds you actually completed, add distance if desired, and tap **Confirm activity**. A shorter confirmed duration counts as partial. Additional confirmed sessions assigned to that same goal can complete it.

Plan lists a planned workout once and groups its contributing sessions under **Workout sessions**. Expand the group to inspect each session separately, even when two sessions completed the same plan. Extra workouts appear under **Activity on this date**. To give one plan credit, open the saved entry, choose **Assign to planned work**, and select the date and a matching uncredited set or cardio goal.

## Exercise catalog

**Exercises** includes 37 offline entries with setup cues and 72 images. The tab opens with native **Search** and a blank results area. Type an exercise name, muscle or equipment, such as `chest` or `dumbbell chest`, to find matches offline. Muscle searches match primary targets when that muscle has a primary tag in the catalog; otherwise, they also use its secondary tags. Search `back` or `legs` on its own to find the corresponding muscle group. Clearing the query hides the results and leaves Search available. Existing custom exercises are searchable by name. To create a text-only custom exercise, open **Choose from exercise library** in the routine editor, then **New custom exercise** in the picker. Open a search result to enlarge a demonstration frame, check the recording method or compare related movements. For example, the flat barbell and dumbbell bench presses share a movement and target muscle, but use different load conventions.

The snapshot uses 36 Everkinetic images distributed by wger under CC BY-SA 3.0. Another 32 frames come directly from Everkinetic’s collection under CC BY-SA 4.0. Each direct-source frame retains its original Git file hash and revision. The app bundles JPEG copies with credits and links to the original records. [Everkinetic source revision and license](https://github.com/everkinetic/data/tree/446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6) · [wger image license](https://creativecommons.org/licenses/by-sa/3.0/)

Four images come from Wikimedia Commons. BruceBlaus illustrated the calf raise and wrist curl under CC BY-SA 4.0. GeorgeStepanek photographed the dumbbell row under CC BY-SA 3.0, and Nenad Stojković (Shixart1985) photographed the forearm plank under CC BY 2.0. The catalog records the source and license for each image and its rewritten exercise instructions. [Catalog and attribution records](App/CatalogResources/catalog.json)

Each bundled image was checked visually against the named movement and its source credit. Of the 37 variants in the acceptance inventory, 22 have a matching demonstration, six need an equipment or grip choice, and nine still need an exact illustration. Form, instructions and redistribution terms await qualified review.

## Progress and recovery

Open **Progress** to see this week’s completed and scheduled workout count with a completion bar. **Last 7 days** charts finished sessions by performed date, with totals for the same seven-day window. Tap or drag across the chart to inspect a day’s sessions. With VoiceOver, adjust the selected date below the chart to move between days. The clock-arrow icon beside **Last 7 days**, labeled **Workout history** for accessibility, opens the full saved history, where you can correct a session’s date, adjust a cardio result, or correct or undo a confirmed set. Records and schedule credit reflect the saved corrections.

**Exercise progress** groups exercises from your active routine by primary muscle, with one card for an exercise repeated across routine days. Cards include a catalog thumbnail when available and the heaviest confirmed working set with that set’s date. Bodyweight exercises show the most reps, timed exercises the longest hold, and assisted exercises the latest assistance value. Exercises without a logged result show **N/A** with the relevant unit. Weight placeholders show **N/A lbs** or **N/A kg**, according to the display setting. A missing set date also shows **N/A**. Comparable records stay separate when recording conventions, machine profiles or sides differ. Tap a card with a result to open its details. If it contains several record series, choose one first. The **Settings** gear opens display units, Lock Screen privacy, and backup and export. Choose pounds or kilograms under **Record display unit**. When every prescribed working set in an eligible exercise reaches the upper rep target at the same load in one session, Progress suggests choosing the next increment. You decide the new weight.

Use **Progress → Settings → Backup and export** to save a CSV for inspection or a versioned Weekform JSON backup for recovery. Keep a copy of the JSON somewhere you can access if you lose the phone. Restoring a backup replaces the current local profile after confirmation. Weekform validates the backup, reopens the staged data to check it, and keeps a copy of the profile from before the replacement. Use **Review pre-restore copy** to inspect that copy before deciding whether to switch back.

## Local development

For an optional private starter, put a local JSON file matching the `WeekPlan` model in `DevelopmentPrivate/LocalStarter.json` and rebuild in Debug. Give it seven ordered days, starting with Monday. It appears under **Choose a starter**. Git ignores JSON files in that directory. The build copies the file into the Debug app when present and excludes it from Release. Keep Debug builds containing a private starter for personal testing.

Open **Developer tools** from the Debug welcome screen, Plan or Routines. **Replay onboarding** starts a new draft and keeps saved routines. **Reset planner test data** asks for confirmation before clearing the routines and draft for this installation. Use reset only with disposable test data. Release builds open the same weekly planner and omit the developer tools.

## Use the workout Live Activity

The workout you most recently started or resumed is the one shown in the Live Activity. The Lock Screen and expanded Dynamic Island can show actions for the current set when iOS allows them. The in-app workout remains available if the activity is dismissed or the device cannot show it.

The compact Dynamic Island displays elapsed rest numerically. The expanded view adds the target, set number and available actions. In the iOS 26.2 and 27.2 simulators, the expanded activity on the Home Screen showed 0:07 elapsed against a 1:30 target for set 2, with **Edit result** and **Start set** visible.

Under **Progress → Settings → Lock Screen privacy**, **Show exercise name** and **Show set values** both default to off. Turn on both to confirm a set from the activity when its full actual values are visible and valid. If they are missing, hidden or too long to display, open the app to check and edit them.

**Confirm & rest** saves the displayed set and starts the configured rest interval. With **No timer**, **Confirm set** just saves the result. Elapsed rest can pass its target without logging a set. **Start set** ends that interval, and **Resume** continues paused rest. **Log final set** finishes the current exercise’s last set. **Next exercise** selects the next unfinished exercise. **Review workout** opens the summary, where finishing the session ends the activity. Repeated or outdated controls cannot credit the next set.

Before the search-only redesign, automated contrast checks at Accessibility Large reported failures on both the full exercise list and exercise detail in light and dark appearances on the iOS 26.2 and 27.2 simulators. The current focused audit of a filtered Barbell curl result reports clipped text in the native search field at Accessibility Large in both light and dark appearances on iOS 26.2, although the sampled query appears fully visible in the captures. Accessibility checks for this search change have not run on iOS 27.2. The broader contrast findings remain open.

### Check on a signed iPhone

Physical-device acceptance remains open for signing, locked and suspended actions, and recovery after interruption. A spoken VoiceOver walkthrough from onboarding through a completed workout also remains open.

Use a dedicated test iPhone with Live Activities enabled. The project has no signing team selected. Before installing on the phone, configure authorized signing for both `Weekform` and `WeekformActivity`. Their provisioning profiles must allow the same App Group, `group.com.christophervalle.weekform`.

1. Using disposable data, start a workout with two exercises and at least two sets each. Set a short rest for the first exercise and **No timer** for the second. Leave both privacy switches off, enter the first set’s actual values in the app, then lock the phone. Check that the activity hides the exercise and values and directs you to Weekform for confirmation.
2. Enable both privacy switches, return to the workout, and lock the phone. When iOS shows the full result, tap **Confirm & rest**. Let rest run past its target and reopen the app. Check that exactly one set is saved. Repeat a stale tap if the old control is still visible and verify the count again.
3. Enter the remaining actuals as needed. Try **Log final set**, then **Next exercise**. On the second exercise, check that **Confirm set** saves without starting rest. Use **Review workout** to finish in the app and verify the activity ends. Record device, OS, lock state and any authentication or presentation limits. Dynamic Island checks require a compatible iPhone.

### Separate development probe

The **Foundation workout** development test exercises a single synthetic set independently of regular training sessions.

1. In Debug, open **Developer tools → Foundation workout**. This separate one-set test uses eight synthetic reps. Check that **Status** reads **Ready**, tap **Start Live Activity**, then lock the phone.
2. On the Lock Screen, tap **Confirm 8 test reps**. Look for **Test set saved**. Unlock the phone and check that the app shows **Saved**. If Live Activities are disabled, you can exercise the in-app path with **Confirm 8 reps**.
3. Force-quit Weekform, reopen it, and go back to **Developer tools → Foundation workout**. **Status** should still read **Saved**, and the confirmation button should be gone. If storage is temporarily unavailable, unlock the phone and tap **Refresh saved result**.

The probe keeps one result across launches. To repeat from **Ready**, use a fresh dedicated simulator for the in-app check or a clean test installation with an empty Weekform App Group on a dedicated phone for the Lock Screen check. Keep resets confined to disposable test data.
