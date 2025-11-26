# capture_serial.py
import serial, time, sys
p = "COM4"
baud = 115200
ser = serial.Serial(port=p, baudrate=baud, timeout=1)
out = open("serial_dump.bin", "wb")
print("Listening... press Ctrl-C to stop")
try:
    start = time.time()
    while time.time() - start < 20:   # capture 20s max
        b = ser.read(1024)
        if b:
            out.write(b)
            out.flush()
            print(f"got {len(b)} bytes")
except KeyboardInterrupt:
    pass
finally:
    ser.close()
    out.close()
    print("dumped to serial_dump.bin")