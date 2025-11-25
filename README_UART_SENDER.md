# UART Image Sender

Python utility to stream images over a UART port (default COM4) to your FPGA design, waiting for a processed response after each image before sending the next.

## Features
- Sequential send with back-pressure (waits for response).
- Two protocol modes:
  - `length`: send start byte (0x5A) + 4-byte length + payload; expect 0xA5 + length + processed bytes.
  - `sentinel`: send raw payload; receive until sentinel token (default `/0/0`).
- Output images stored as `<input_stem>_<id><ext>` in `output/`.
- Per-image CSV log in `output_csv/` named `<input_stem>.csv` (append rows).
- Optional resize on input; optional reconstruction of grayscale output via `--out-width/--out-height`.

## Install
```powershell
pip install -r requirements.txt
```

## Usage Examples
### Length-based (recommended)
```powershell
python send_images_uart.py --input-dir images --mode length --in-width 128 --in-height 128 --out-width 64 --out-height 64 --port COM4 --baud 115200 --log-level INFO
```
### Sentinel-based
```powershell
python send_images_uart.py --input-dir images --mode sentinel --sentinel /0/0 --port COM4
```

## CSV Columns
`id,input_name,bytes_sent,bytes_received,duration_s,output_image_path,mode,success,timestamp`

## Adapting to Your FPGA
- Ensure your FPGA transmitter matches the chosen mode. If you simplified TX to raw streaming without markers, implement the length header in hardware for reliability.
- If using grayscale output of half resolution, set `--out-width/--out-height` appropriately (e.g., 64 64 for 128x128 -> 64x64).
- Extend protocol easily: prepend additional metadata fields before payload; update script accordingly.

## Troubleshooting
- Timeout errors: increase `--read-timeout` or verify hardware responds promptly.
- Size mismatch on image reconstruction: script will fallback to raw byte dump; inspect `.csv` and adjust dimensions.
- Permission/port busy: close other terminal/Vivado serial monitors.

## License
Internal use only.
