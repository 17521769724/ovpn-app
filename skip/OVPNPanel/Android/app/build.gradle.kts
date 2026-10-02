import java.util.Properties

plugins {
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.android.application)
    id("skip-build-plugin")
}

skip {
}

android {
    namespace = group as String
    compileSdk = libs.versions.android.sdk.compile.get().toInt()
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString())
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
    }

    defaultConfig {
        minSdk = libs.versions.android.sdk.min.get().toInt()
        targetSdk = libs.versions.android.sdk.compile.get().toInt()
        // skip.tools.skip-build-plugin 会自动采用 Skip.env 中的配置：
        // applicationId = PRODUCT_BUNDLE_IDENTIFIER
        // versionCode   = CURRENT_PROJECT_VERSION
        // versionName   = MARKETING_VERSION
    }

    // Skip Fuse 模式下需要打包 Swift runtime .so；Lite 模式下无副作用
    packaging {
        jniLibs {
            keepDebugSymbols.add("**/*.so")
            pickFirsts.add("**/*.so")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    lint {
        disable.add("Instantiatable")
        disable.add("MissingPermission")
        // OpenVPN 库通过清单合并注入 VpnService，lint 无法静态追踪
        disable.add("ProtectedPermissions")
        abortOnError = false
    }

    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    signingConfigs {
        val keystorePropertiesFile = file("keystore.properties")
        create("release") {
            if (keystorePropertiesFile.isFile) {
                val keystoreProperties = Properties()
                keystoreProperties.load(keystorePropertiesFile.inputStream())
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            } else {
                // 无 keystore.properties 时退回 debug 签名（CI 产物可直接侧载安装）
                keyAlias = signingConfigs.getByName("debug").keyAlias
                keyPassword = signingConfigs.getByName("debug").keyPassword
                storeFile = signingConfigs.getByName("debug").storeFile
                storePassword = signingConfigs.getByName("debug").storePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            // OpenVPN 3 内核依赖反射与 JNI，关闭混淆以避免运行时找不到符号
            isMinifyEnabled = false
            isShrinkResources = false
            isDebuggable = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

// skip-build-plugin 会自动注入依赖 "com.ovpn.panel:OVPNPanel"（不带版本号），
// 期望由 includeBuild 的默认替换指向本地转译模块。实际构建中该替换未生效，
// 报错：Could not find com.ovpn.panel:OVPNPanel:。
// 这里显式把该坐标替换为工程内同名模块（由 Skip 的 settings 插件 include 进来），
// 与 `skip export` 生成的兜底插件所用的 project(":OVPNPanel") 写法一致。
val hasTranspiledAppModule = findProject(":OVPNPanel") != null

configurations.configureEach {
    resolutionStrategy.dependencySubstitution {
        if (hasTranspiledAppModule) {
            substitute(module("com.ovpn.panel:OVPNPanel")).using(project(":OVPNPanel"))
        }
    }
}

dependencies {
    // OpenVPN 3 内核：与改造前 Android 版完全一致，保证 VPN 行为不变
    implementation("io.github.tim06:openvpn:1.1.3")
    implementation("io.github.tim06:basevpnprotocols:1.1.0")
    implementation("io.github.tim06:vpnprotocolsnotification:1.1.0")
}
