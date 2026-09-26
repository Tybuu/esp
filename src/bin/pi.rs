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
use embassy_futures::join::join;
use embassy_time::{Duration, Timer};
use esp_hal::dma::DmaRxBuf;
use esp_hal::dma_buffers;
use esp_hal::dma_tx_buffer;
use esp_hal::gpio;
use esp_hal::gpio::Input;
use esp_hal::gpio::InputConfig;
use esp_hal::gpio::Output;
use esp_hal::gpio::OutputConfig;
use esp_hal::peripherals;
use esp_hal::spi::master::Spi;
use esp_hal::time::Rate;
use esp_hal::timer::timg::TimerGroup;
use esp_hal::uart::Uart;
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
async fn main(spawner: Spawner) {
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

    let mut hid_uart = Uart::new(
        peripherals.UART2,
        esp_hal::uart::Config::default().with_baudrate(3_000_000),
    )
    .unwrap()
    .into_async()
    .with_rx(peripherals.GPIO10)
    .with_tx(peripherals.GPIO11);

    let mut input = Input::new(
        peripherals.GPIO12,
        InputConfig::default().with_pull(gpio::Pull::Down),
    );

    let _ = spawner;
    let (mut rx, _) = uart.split();
    let uart_task = async {
        let mut buf: Vec<u8, 2048> = heapless::Vec::new();
        loop {
            let mut tmp = [0u8; 1];
            match rx.read_exact_async(&mut tmp).await {
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
    };
    let spi_task = async {
        let (mut rx, mut tx) = hid_uart.split();
        let read_task = async {
            let mut state = ReadState::Header1;
            let mut buffer = [0u8; 32];
            loop {
                match state {
                    ReadState::Header1 => {
                        if rx.read_async(&mut buffer[..1]).await.is_ok() && buffer[0] == 0xA5 {
                            esp_println::println!("[ESP UART RX] HEADER1 Received");
                            state = ReadState::Header2;
                        }
                    }
                    ReadState::Header2 => {
                        if rx.read_async(&mut buffer[..1]).await.is_ok() && buffer[0] == 0x55 {
                            esp_println::println!("[ESP UART RX] HEADER2 Received");
                            state = ReadState::Payload;
                        }
                    }
                    ReadState::Payload => {
                        if rx.read_exact_async(&mut buffer).await.is_ok() {
                            esp_println::println!("[ESP UART RX] {:?}", buffer);
                        }
                        state = ReadState::Header1;
                    }
                }
            }
        };
        let write_task = async {
            let mut buffer = [0u8; 34];
            buffer[0] = 0xA5;
            buffer[1] = 0x55;
            buffer[2] = 0x3;
            buffer[3] = 1;
            buffer[4] = 5;
            buffer[5] = 0;
            loop {
                input.wait_for_high().await;
                let _ = tx.write_async(&buffer[0..6]).await;
                esp_println::println!("[ESP UART TX] Wrote {:?}", &buffer[0..6]);
                Timer::after_millis(500).await;
            }
        };
        join(read_task, write_task).await;
    };
    join(uart_task, spi_task).await;
}

enum ReadState {
    Header1,
    Header2,
    Payload,
}
