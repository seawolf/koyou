# Android builds

Part of the notes for AI agents; start from [AGENTS.md](../../AGENTS.md). Read
this before chasing a warning from `flutter build apk` or touching `android/`.

## An Android build warning that is not a bug

It appears on every `flutter build apk`. It does not break the build, and it is
not fixable here. Do not spend an afternoon on it again.

There used to be two. The other — `java.lang.System::load has been called by
... NativeLibraryLoader` — was Gradle's own `native-platform` JAR calling a
restricted method on a newer JDK, from the launcher JVM, so no
`org.gradle.jvmargs` could silence it. It went away with Gradle 9.9.0, as
expected; if it comes back after a Gradle downgrade, that is why.

**`Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP):
flutter_tts`** — this one is real, and will eventually fail rather than warn.
The switch is `android.builtInKotlin` in `android/gradle.properties`, which the
Flutter template sets to `false`. Setting it to `true` fails immediately and
says exactly why:

```
> Failed to apply plugin 'kotlin-android'
  Solution: Remove the 'org.jetbrains.kotlin.android' plugin from this
  project's build file: .../flutter_tts-4.2.5/android/build.gradle
```

So the blocker is entirely inside `flutter_tts`, not here — **this app is
already on built-in Kotlin**: its `plugins` block applies only
`com.android.application` and the Flutter plugin, and the
`org.jetbrains.kotlin.android` line in `settings.gradle.kts` is `apply false`,
a version declaration rather than an application.

Switching packages does not help. `stts`, the obvious alternative, has not
migrated either — its changelog moved to the Kotlin Gradle *DSL*, which is a
different thing. The fix is upstream; when `flutter_tts` ships it, flip
`android.builtInKotlin` to `true` and check the build.
