# Repository Guidelines

## Project Structure & Module Organization
This is a Garmin Connect IQ (Monkey C) app. Core logic lives in `source/` with one class per file (e.g., `source/MainView.mc`). UI resources live in `resources/` (`resources/layouts`, `resources/menus`, `resources/strings`, `resources/drawables`). The project manifest is `manifest.xml`, and the build config is `monkey.jungle`. Build outputs and generated artifacts typically land in `bin/`, `gen/`, `mir/`, and `internal-mir/`.

## Build, Test, and Development Commands
There are no repo scripts; use the Connect IQ SDK CLI directly.
- Build (example): `monkeyc -o bin/NutritionAiAssistantApp.prg -f monkey.jungle -y <developer_key>` builds the app using `monkey.jungle`.
- Run in simulator (example): `monkeydo bin/NutritionAiAssistantApp.prg <device>` launches the app in the device simulator.
Adjust `<developer_key>` and `<device>` to your local SDK setup.

## Coding Style & Naming Conventions
- Indentation: 4 spaces in Monkey C (`.mc`) files.
- Naming: classes and files use PascalCase (e.g., `MainMenuDelegate`, `MainMenuDelegate.mc`); methods are camelCase.
- Imports: group `using`/`import` statements at the top of the file.
No formatter or linter is configured in this repo; keep style consistent with existing files in `source/`.

## Testing Guidelines
No automated tests are present. Validate changes with manual testing in the Connect IQ simulator and on a target device where possible. If you add tests or helpers, document how to run them here.

## Commit & Pull Request Guidelines
Commit history uses short, capitalized, imperative-style messages (e.g., “Add pairing”, “Update backend URL”). Keep subjects under ~72 characters when possible.
For pull requests, include:
- A brief description of the change and rationale.
- Screenshots for UI changes.
- Any relevant device/simulator notes or limitations.

## Configuration & Security Notes
If you change endpoints or API details, update related resources and document required configuration. Avoid committing secrets; use local config or SDK key files as needed.
