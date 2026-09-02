#![no_std]
#![no_main]
#![deny(
    clippy::mem_forget,
    reason = "mem::forget is generally not safe to do with esp_hal types, especially those \
    holding buffers for the duration of a data transfer."
)]
#![deny(clippy::large_stack_frames)]

use defmt::Format;
use defmt::info;
use embassy_executor::Spawner;
use embassy_time::{Duration, Timer};
use esp_hal::gpio;
use esp_hal::gpio::Output;
use esp_hal::timer::timg::TimerGroup;
use esp_hal::{clock::CpuClock, interrupt::software::SoftwareInterrupt};
use heapless::Vec;
use {esp_backtrace as _, esp_println as _};

// This creates a default app-descriptor required by the esp-idf bootloader.
// For more information see: <https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/app_image_format.html#application-description>
esp_bootloader_esp_idf::esp_app_desc!();

#[allow(
    clippy::large_stack_frames,
    reason = "it's not unusual to allocate larger buffers etc. in main"
)]
#[esp_rtos::main]
async fn main(spawner: Spawner) -> ! {
    // generator version: 1.1.0

    let config = esp_hal::Config::default().with_cpu_clock(CpuClock::max());
    let peripherals = esp_hal::init(config);

    let timg0 = TimerGroup::new(peripherals.TIMG0);
    let sw_int =
        esp_hal::interrupt::software::SoftwareInterruptControl::new(peripherals.SW_INTERRUPT);
    esp_rtos::start(timg0.timer0, sw_int.software_interrupt0);

    info!("Embassy initialized!");
    let mut uart_config = esp_hal::uart::Config::default().with_baudrate(115_200);
    let mut uart = esp_hal::uart::Uart::new(peripherals.UART1, uart_config)
        .unwrap()
        .into_async()
        .with_rx(peripherals.GPIO16)
        .with_tx(peripherals.GPIO17);
    // TODO: Spawn some tasks
    let _ = spawner;
    let mut buf: Vec<u8, 2048> = heapless::Vec::new();
    loop {
        let mut tmp = [0u8; 1];
        match uart.read_exact_async(&mut tmp).await {
            Ok(_) => {
                if tmp[0] as char == '\n' {
                    match str::from_utf8(&buf) {
                        Ok(str) => {
                            esp_println::println!("{}", str);
                            // info!("{}", str)
                        }
                        Err(err) => {
                            defmt::error!("Failed at {}", &err.valid_up_to());
                        }
                    }
                    buf.clear();
                } else if buf.push(tmp[0]).is_err() {
                    match str::from_utf8(&buf) {
                        Ok(str) => {
                            esp_println::println!("{}", str);
                            // info!("{}", str)
                        }
                        Err(err) => {
                            defmt::error!("Failed at {}", &err.valid_up_to());
                        }
                    }
                    buf.clear();
                }
            }
            Err(err) => {
                defmt::error!("Uart Error: {}", err);
                buf.clear();
            }
        }
    }

    // for inspiration have a look at the examples at https://github.com/esp-rs/esp-hal/tree/esp-hal-v~1.0/examples
}
