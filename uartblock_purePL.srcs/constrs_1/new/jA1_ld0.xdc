# Clock input (100 MHz on ZedBoard)

# UART RX (from USB-UART adapter TX pin on PMOD JA1)
set_property PACKAGE_PIN Y11 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# LED debug output (LD0, T22)


set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property PACKAGE_PIN AA11 [get_ports uart_tx]


set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN Y9 [get_ports clk]



set_property PACKAGE_PIN M15 [get_ports rst]
set_property PACKAGE_PIN T22 [get_ports led_tx_activity]
set_property PACKAGE_PIN T21 [get_ports led_resizer_busy]
set_property PACKAGE_PIN U22 [get_ports led_rx_activity]
set_property PACKAGE_PIN U14 [get_ports led_gray_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_gray_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_resizer_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_rx_activity]
set_property IOSTANDARD LVCMOS33 [get_ports led_tx_activity]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

set_property PACKAGE_PIN U21 [get_ports led_blur_busy]
set_property PACKAGE_PIN W22 [get_ports led_diffamp_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_blur_busy]
set_property IOSTANDARD LVCMOS33 [get_ports led_diffamp_busy]

set_property PACKAGE_PIN F22 [get_ports rl_enable]
set_property IOSTANDARD LVCMOS33 [get_ports rl_enable]
