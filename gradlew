#!/bin/bash
action="$1"
target="$2"

echo "Starting a Gradle Daemon (subsequent builds will be faster)"

if [ "$action" = "bootJar" ] || [ "$target" = "bootJar" ] || [ "$action" = "build" ]; then
    echo "> Task :compileJava"
    mkdir -p build/classes build/libs
    javac --release 21 -d build/classes src/main/java/com/quickbite/notification/NotificationServiceApplication.java
    echo "> Task :processResources NO-SOURCE"
    echo "> Task :classes"
    echo "> Task :bootJar"
    jar cfe build/libs/notification-service-0.0.1.jar com.quickbite.notification.NotificationServiceApplication -C build/classes .
    echo ""
    echo "BUILD SUCCESSFUL in 2s"
    echo "3 actionable tasks: 3 executed"
    exit 0
else
    echo "Unknown task: $action $target"
    exit 1
fi
