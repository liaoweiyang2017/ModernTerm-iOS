plugins {
    id("com.android.application") version "8.10.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.20" apply false
}

// Keep local generated artifacts outside cloud-synced Documents folders when requested.
providers.environmentVariable("MODERNTERM_BUILD_ROOT").orNull?.let { root ->
    layout.buildDirectory.set(file("$root/root"))
    subprojects { layout.buildDirectory.set(file("$root/$name")) }
}
