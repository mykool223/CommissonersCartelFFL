# kotlinx.serialization keeps its serializers via generated companions.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.commissionerscartel.app.** {
    *** Companion;
}

# Room finds its generated implementation by name at runtime — WorkDatabase
# looks for WorkDatabase_Impl — so R8 cannot see the reference and strips the
# no-argument constructor it needs. The app then dies before it draws
# anything, with "Failed to create an instance of androidx.work.impl
# .WorkDatabase" and no hint that shrinking caused it.
#
# Nothing here uses Room or WorkManager directly. Both arrive with the Glance
# widget, which is why this only appeared once the widget shipped.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.room.RoomDatabase$* { *; }
-dontwarn androidx.room.paging.**

# The widget's own receiver and its Glance implementation are found by the
# system from the manifest and by name, not by any call R8 can follow.
-keep class com.commissionerscartel.app.widget.** { *; }
