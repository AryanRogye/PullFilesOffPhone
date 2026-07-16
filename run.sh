#!/bin/bash

xcodebuild \
  -project PullFilesOffPhone.xcodeproj \
  -scheme PullFilesOffPhone \
  -configuration Debug \
  -derivedDataPath ./DerivedData

./DerivedData/Build/Products/Debug/PullFilesOffPhone
