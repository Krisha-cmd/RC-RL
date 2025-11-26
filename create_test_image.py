#!/usr/bin/env python3
"""Create a test image with cyan and yellow for FPGA testing"""
from PIL import Image

# Create 128x128 image with cyan top half, yellow bottom half
img = Image.new('RGB', (128, 128))
pixels = []

for y in range(128):
    for x in range(128):
        if y < 64:
            pixels.append((0, 255, 255))  # Cyan (R=0, G=255, B=255)
        else:
            pixels.append((255, 255, 0))  # Yellow (R=255, G=255, B=0)

img.putdata(pixels)
img.save('input/test_cyan_yellow.png')
print("Created input/test_cyan_yellow.png - 128x128 with cyan top, yellow bottom")
print("Cyan = (0, 255, 255), Yellow = (255, 255, 0)")
