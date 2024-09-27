---
layout: post
title: "Don't snipe me in space - intentional flash corruption for STM32 microcontrollers"
image: assets/stm32/sniper.jpg
---

Almost one and a half years ago I joined [MOVE](https://warr.de/en/projects/move/), the **M**unich **O**rbital **V**erification **E**xperiment, a student club focusing on practical education in the area of satellites at the [Technical University of Munich](https://www.tum.de/). MOVE has launched three CubeSats to date ([First-MOVE in 2013](https://warr.de/en/projects/move/first-move/), [MOVE-II in 2018 and MOVE-IIb in 2019](https://warr.de/en/projects/move/move-ii-and-move-iib/)), and we are currently preparing two future missions. These missions require reliable software, and the ability to update in orbit.

One of the first larger projects I took part in was building a bootloader for the [STM32L4R5ZI MCU](https://www.st.com/en/microcontrollers-microprocessors/stm32l4r5-s5.html), which should enable us to do reliable on-orbit software updates. This MCU has 2 MB of flash storage, which we use to store the bootloader, firmware images and additional metadata (e.g. checksums for firmware images).

### Bootloader requirements and reliability

The bootloader, which is written in Rust, is the first part of our software stack that runs. It has to be extremely reliable, even in really weird situations, because a failure of the bootloader could lead to a loss of the MCU or even the entire mission (depending on the exact design of the remaining system).

Let's first take a look at what the bootloader actually does. It manages **3 slots** for operating system images, with each having around 500 KB reserved for it. Additionally, **2 redundant metadata** structs are stored on different flash pages. During an update, one slot is overwritten, and then metadata is adjusted. We are resilient against power failures at any point, and as long as at least one image slot contains an operating system image, we can boot.

To ensure all of this works as expected, we verify some properties using [Kani](https://model-checking.github.io/kani/), and we guarantee that no panic handler ends up in the binary (this mostly requires the compiler to prove that no bounds checks can fail, thus optimizing them away, thus making panic unreachable). We also have hardware tests in our CI pipeline that run against the actual bootloader on the target MCU, of which multiple are connected to a self-hosted GitLab runner. Additionally, we use the watchdog of the MCU to reset the chip in case our code would get stuck in some endless loop.

While this gets us pretty far, there are still some situations we have not yet handled, especially regarding interrupts. We don't actually care about most interrupts in the bootloader, so we just tell the CPU to not handle them. Easy, right?

Well, it's not that easy. There are some situations where a non-maskable interrupt (NMI) will be triggered, and you **can't ignore them**. One of them is the ECCD non-maskable interrupt (ECC detection).

### Flash ECC and related interrupts

The microcontroller has 2MB of flash storage with ECC. This means that for every 64 bit, it stores an additional 8 bits of error checking information. When reading from the flash, this information is automatically checked to detect bit flips. These can happen for a variety of reasons. In the case of satellites, radiation exposure can be a cause.

The manual states the following about what happens when you read from a block with one or more bit flips:

> When one error is detected and corrected, the flag ECCC (ECC correction) is set in Flash ECC register (FLASH_ECCR). If ECCCIE is set, an interrupt is generated.
>
> When two errors are detected, a flag ECCD (ECC detection) is set in FLASH_ECCR register. In this case, a NMI is generated.

If we have the first situation, that's fine, because we just read and get the correct value. The second one is the problem, because it **disrupts our program flow**. Even worse, if this error happens when reading an operating system image, and we were to always try the same one (we have some mitigation against this), we could land in a boot loop if we don't handle the situation.

Writing a handler for the flash ECCD NMI isn't particularly hard using the [cortex_m_rt](https://docs.rs/cortex-m-rt/latest/cortex_m_rt/) and [stm32l4](https://docs.rs/stm32l4/latest/stm32l4/) crates:

```rust
#[cortex_m_rt::exception]
unsafe fn NonMaskableInt() -> ! {
	let peripherals = unsafe { stm32l4r5::Peripherals::steal() };
	let reg_content = peripherals.FLASH.eccr.read();
	let is_flash_nmi: bool = {
		/// Note: initializes our custom flash abstraction
		let flash = Flash::new(peripherals.FLASH);
		if flash.is_dualbank() {
			/// In dual-bank mode, Bit 29 (ECCD2) is reserved, so only look at bit 31 (ECCD)
			reg_content.eccd().bit_is_set()
		} else {
			/// Bit 31 and Bit 29 - either lower or upper 64 bits of 128 bit value
			const ECCD_ECCD2_MASK: u32 = 0xa0000000;
			reg_content.bits() & ECCD_ECCD2_MASK != 0
		}
	};

	/// Address on 1MB bank + which bank it's on
	let dead_addr = reg_content.addr_ecc().bits() | ((reg_content.bk_ecc().bit() as u32) << 20);

	/// Some actual logic to handle this information
	if is_flash_nim {
		/// dead_addr has problems
	}
}
```

We essentially check a few bits to know that this is actually the flash ECCD NMI, and then extract the flash address of the offending 64 bit block.

In our bootloader we can now enable a custom boot mode that ensures that if at least one image is bootable, it is booted, which will enable us to fix this problem remotely.

That's the theory. But how can we ensure that this works, and that our code handles this situation correctly? Usually, we would just run it in our tests, and see how it's doing.  However, since this handles a specific interrupt, we somehow need to trigger it intentionally. In other words, we need to mark certain blocks of the flash to make them trigger ECCD NMIs.

### Placing ECCD NMIs
The STM32L4R5, as far as I know, does not offer a feature that enables us to generate an NMI on a custom-defined flash address. But that is exactly what we need to test our interrupt handler.

So I set out to explore my favorite RM0432 reference manual a bit more and found this interesting note:

> Note: The contents of the Flash memory are not guaranteed if a device reset occurs during a Flash memory operation.

This gave me hope that it might be possible to corrupt a block when triggering a reset during a write operation, so I got to writing a small program that does the following:
- First, the program reads the flash address it should corrupt
  - If it is already corrupted, the NMI handler will be executed. I've written one that turns on the green LED of the chip
- Enable the hardware watchdog to reset us after a fixed time interval
- Spend the majority of that time interval in a loop that busy-waits
- Just towards the end, start a write operation into the flash

Then hopefully, the watchdog would reset us exactly when the write operation happens. And that actually turned out to work sometimes, I was really happy when I first saw the green LED come on.

To verify that the code actually did what I thought, I connected GDB to the chip and read out the `FLASH_ECCR` register, which contains information about flash ECC interrupts:

```
(gdb) x/wx 0x40022018
0x40022018:     0x80006000
```

In the value `0x80006000`, the top bit means that the interrupt is actually the ECCD interrupt. The lowest 20 bit, or the last 5 hex characters, are the address of the block that was found to have two or more errors. This was exactly the address I had configured it to damage, so it was really nice to see it work as intended.

However, this would only work sometimes. The wait time can vary due to timings being slightly different, depending on temperature and other things, so a more dynamic approach that finds the correct timing was required.


#### Binary search over multiple resets
The approximate unit of time to wait varies a bit, but is in a certain range. In this case "unit of time" really just means how much overhead an almost empty loop has, because that's what I used to wait before the flash programming start (there are honestly better ways, but this is one way, and it works).

So what I wanted to build is a binary search that keeps its state over resets. Keeping state is kind of the opposite of what a reset is intended to do, so a way to store data across resets was needed. The real time clock (RTC) of the MCU has 32 backup registers, which store 32 bits each. They are kept over multiple resets and thus enable us to keep state such as the bottom and top of the range that we are searching.

When doing a step, we first calculate the middle of the waiting range, busy-wait that amount of iterations, and then initiate flash programming. Once it's finished, the blue LED turns on. Afterwards (or hopefully *during* the programming operation), the watchdog reset happens. The blue LED thus indicates that we need a lower timing. If the process worked, the green LED comes on, otherwise a next reset happens. If the program got into a spot where it cannot advance further (timings are a bit random after all), the red LED will come on. In that case, a manual reset can be done.

With that in mind, this is what destroying an address looks like in practice (Note the LD1-LD2 LEDs):

<p>
<video controls muted style="width:100%;height:100%;margin-left:auto;margin-right:auto;object-fit:cover">
    <source src="assets/stm32/flash-corruption.mp4" type="video/mp4">

</video></p>


That's essentially the entire thing in action. If the blue LED comes on, we have missed the point where we can interrupt, so once the watchdog triggers, we try again with a lower value. After a short pause of not seeing the LED turn on (this is where we took too little time and stopped before even programming the flash), short pulses return. At some point, we get the right timing, leading to a flash ECCD NMI, which is handled by turning on the green LED.

I uploaded the program to [GitHub](https://github.com/xarantolus/stm32-flash-corruptor), so feel free to use it in your own testing.

### Testing the bootloader
With this new tool under our belt, we can now intentionally affect flash addresses, especially ones on the metadata and image slot pages. Using the tool, I was able to verify that the bootloader can still boot our operating system even if **all metadata pages** and **all but one operating system image** contain a block where reading leads to an NMI.

This now gives me a reasonable peace of mind, even when the bootloader will be in space. To be honest, I will probably still have some worries for my first code in space, but at least now there is one less unknown.

### Final note
If you think this kind of stuff is interesting and your company might be interested in supporting or sponsoring our [student club](https://warr.de/en/projects/move/), please reach out to me at [philipp.erhardt@warr.de](mailto:philipp.erhardt@warr.de). Additionally, if your company has some space left on a satellite and wants to enable the next generation of builders to get hands-on experience, please also reach out. We are thankful for any support.

If you're interested in hearing more about MOVE, satellites, or just want to stay updated on things like this, feel free to subscribe to the RSS feed of my blog or follow me on [LinkedIn](https://www.linkedin.com/in/erhardt-philipp/).

Thank you for reading!
