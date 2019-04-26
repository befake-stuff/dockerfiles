#! /bin/bash
#############################
#   TF 1.7 Testing Script   #
#############################

# TF Session
python mnist_session.py

# TF Estimator
python mnist_estimator.py

# TF Eager
python mnist_eager.py

# Keras Test
python keras_mnist_test.py

# Delete benchmarks folder if exists
if test -d benchmarks; then
	rm -rf benchmarks
fi

# Clone Benchmarks and go to a certain commit
git clone --branch cnn_tf_v1.13_compatible https://github.com/tensorflow/benchmarks.git
cd benchmarks/scripts/tf_cnn_benchmarks

# Check if GPU is installed (quick hack)
which nvidia-smi &> /dev/null
ISGPU=$?

if test $ISGPU -eq 1; then
	# CPU or CPU2?
	NCORE=`cat /proc/cpuinfo | grep processor | wc -l`

	# Quick Benchmark on AlexNet (syntethic images, no data transformation, channel last)
	if test $NCORE -eq 2; then
		# CPU test (defined initial lr otherwise Loss is NaN )
		python tf_cnn_benchmarks.py --device=cpu  --kmp_blocktime=0 --nodistortions --model=alexnet --data_format=NHWC --batch_size=32  --num_inter_threads=1 --num_intra_threads=$NCORE --init_learning_rate=0.00001
	else
		# CPU2 test
		python tf_cnn_benchmarks.py --device=cpu  --kmp_blocktime=0 --nodistortions --model=alexnet --data_format=NHWC --batch_size=64  --num_inter_threads=1 --num_intra_threads=$NCORE --init_learning_rate=0.00001
	fi
else
	GPU_DEV_NAME=$(python -c 'from __future__ import print_function; import tensorflow as tf; print(tf.test.gpu_device_name())' 2> /dev/null)
	case ${GPU_DEV_NAME} in
	/device:GPU:*)
		echo "GPU load test passed. Device found: ${GPU_DEV_NAME}"
		;;
	*)
		echo "ERROR: Tensorflow not able to find GPU device! Device found: ${GPU_DEV_NAME}"
		exit 1
		;;
	esac

	# GPU or GPU2?
	nvidia-smi | grep -q V100
	ISV100=$?

	# Quick Benchmark on Resnet-50 (syntethic images, no data transformation, channel first)
	if test $ISV100 -eq 1; then
		# GPU test
		python tf_cnn_benchmarks.py --device=gpu --num_gpus=1 --batch_size=64 --model=resnet50 --nodistortions --data_format=NCHW
	else
		# GPU2 test (with MXP)
		python tf_cnn_benchmarks.py --device=gpu --num_gpus=1 --batch_size=256 --model=resnet50 --nodistortions --data_format=NCHW --use_fp16=true
	fi
fi

