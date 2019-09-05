#! /bin/bash
######################
# PYTORCH 0.3.1 TEST #
######################

pip install psutil

# Tensorboard X demo
python tensorboardx.py

# Simple DNN MNIST example
python mnist.py

# # Check if GPU is installed (quick hack)
which nvidia-smi &> /dev/null
ISGPU=$?

if test $ISGPU -eq 1; then
	# CPU or CPU2?
	NCORE=`cat /proc/cpuinfo | grep processor | wc -l`

	# Quick Benchmark on AlexNet (syntethic images, no data transformation, channel first)
	if test $NCORE -eq 2; then
		# Stress Test
        python benchmark.py --batch-size=32
	else
		# CPU2 test
		# Stress Test
        python benchmark.py --batch-size=64
	fi
else
	HAS_GPU=$(python -c 'from __future__ import print_function; import torch; print(torch.cuda.is_available())')
	if [ "${HAS_GPU}" = "True" ]; then
		echo "GPU load test passed."
	else
		echo "ERROR: Not able to load GPU in Pytorch"
		exit 1
	fi

	# GPU or GPU2?
	nvidia-smi | grep -q V100
	ISV100=$?

	# Quick Benchmark on Resnet-50 (syntethic images, no data transformation, channel first)
	if test $ISV100 -eq 1; then
		# Stress Test
        python benchmark.py --batch-size=64
	else
		# GPU2 test (with MXP)
		python benchmark.py --batch-size=256 --fp16
	fi
fi
