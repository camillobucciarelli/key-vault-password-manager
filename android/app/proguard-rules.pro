-dontwarn ch.qos.logback.classic.Level
-dontwarn ch.qos.logback.classic.Logger
-dontwarn ch.qos.logback.classic.LoggerContext
-dontwarn ch.qos.logback.classic.spi.ILoggingEvent
-dontwarn ch.qos.logback.classic.spi.LoggingEvent
-dontwarn java.lang.ProcessHandle
-dontwarn java.lang.management.ManagementFactory
-dontwarn java.lang.management.RuntimeMXBean
-dontwarn javax.naming.InitialContext
-dontwarn javax.naming.NameNotFoundException
-dontwarn javax.naming.NamingException
-dontwarn sun.reflect.Reflection

# flutter_autofill_service: keep Moshi-generated adapters and data classes
# used by AutofillMetadata / SaveInfoMetadata JSON serialisation
-keep class com.keevault.flutter_autofill_service.** { *; }
-keepnames class com.keevault.flutter_autofill_service.** { *; }
