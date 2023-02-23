---
layout: post
title: How to fix fastboot device not visible and recovery flashing being stuck on Windows 11
excerpt: "This post shows how to fix two errors I ran into while flashing a custom recovery image using fastboot on Windows 11."
---

I like trying out different Android-based operating systems and recoveries on my phone. A recovery partition is basically a small operating system that runs on your phone and allows you to do things like flashing a new operating system or overwrite certain partitions. If you have used [Magisk](https://github.com/topjohnwu/Magisk) before, you've probably used a custom recovery to flash a patched boot image to root your phone.

The basic steps to installing a recovery are the following:
* Make sure you have `adb` and `fastboot` installed on a PC
* Put the phone in fastboot mode (usually by pressing the power button and volume down button at the same time while booting)
* Run `fastboot devices` to make sure the device is visible to fastboot
  * This is where I had the first problem, a fix for Windows 11 is described below
* Flash the recovery image
  * This is where I had a second problem: the flashing process seemed to be stuck forever. However, I could also fix this

Now let's get into installing a custom recovery.

### Make the device visible to fastboot
To install a custom recovery, we use the `fastboot` tool. If you don't have it installed, visit the [official Android developer page](https://developer.android.com/studio/releases/platform-tools) and download the latest version for your operating system.

Put your device into fastboot mode and make sure it is recognized:

	fastboot devices

However, my device didn't show up in this list, despite being in fastboot mode.

It took me ages to find the fix for that, so I decided to write this post to help others who might run into the same problem.

At first I installed the [Universal ADB Drivers](https://adb.clockworkmod.com/) and made sure my `adb` and `fastboot` tools were at the latest version. However, neither of these fixed the problem.

At some point I found something interesting in the Windows 11 Update Settings: when going to Windows Update > Advanced Options > Optional Updates, there were some Driver Updates related to Android tools. I installed them and tried again. This time, my device showed up in the list of devices.

### Flashing the recovery image
Now it was time to flash the recovery image.

Installing a new custom recovery is rather easy if you know a bit on how to use command-line tools. When I recently installed OrangeFox, I downloaded [the version for my phone](https://orangefox.download/device/chiron) (yours will very likely be different, check your device codename etc!), unzipped the zip file and ran the following command in the folder where the recovery image was located:

	fastboot flash recovery recovery.img

Fastboot was able to find my device, but the flashing process seemed to be stuck forever. After a few minutes I unplugged my phone and plugged it back in and also rebooted into fastboot mode. However, the flashing process was still stuck. I also used different USB cables, but to no avail.

What did fix the problem was the following:
1. Make sure the device is in fastboot mode
2. Unplug the device from the computer
3. Now run the following command:

		fastboot flash recovery recovery.img

4. This should show the `< waiting for any device >` message
5. Plug the device back in and wait for the flashing process to finish

This is the process that worked for me. While a bit of a weird hack, in the end it worked and I was able to flash the custom recovery.

I hope this helped you fix the problem.
