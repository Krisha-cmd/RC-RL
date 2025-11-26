import serial
s = serial.Serial('COM4', 115200, timeout=1)
s.write(b'Tfwejndm')            # trigger self-test
print(s.read(8))         # read up to 8 bytes, should see b'TEST\n'
s.close()