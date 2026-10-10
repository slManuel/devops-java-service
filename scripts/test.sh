#!/usr/bin/env sh
set -eu
mkdir -p build/classes build/test-classes
javac --release 21 -d build/classes src/main/java/demo/Main.java
javac --release 21 -cp build/classes -d build/test-classes src/test/java/demo/SmokeTest.java
java -cp build/classes:build/test-classes demo.SmokeTest
