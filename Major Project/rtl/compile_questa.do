# Run from this directory in QuestaSim: vsim -do compile_questa.do
vlib work
vlog -sv -f filelist.f
# once you have a testbench, e.g.:
# vsim work.tb_top
# add wave -r /*
# run -all
