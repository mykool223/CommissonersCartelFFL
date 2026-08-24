# kotlinx.serialization keeps its serializers via generated companions.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.commissionerscartel.app.** {
    *** Companion;
}
