#!/usr/bin/env python
# -*- coding:utf-8 -*-

from subprocess import check_call
import sys
try:
    import httplib
except:
    import http.client as httplib
import os
import logging
import yaml
import click
import click_log
from .utils import (
    assert_image_tag_from_dockerfile,
    find_matrix_from_dockerfile,
    gen_target_env_from_tag,
    gen_target_cfg_items,
    gen_target_env_cfg,
    gen_dockerfile_path_from_tag,
)

logger = logging.getLogger(__name__)
click_log.basic_config(logger)


@click.command()
@click.argument('dockerfile_or_tag')
@click.option('--use-nvidia-driver/--no-use-nvidia-driver',
              help='Run test with nvidia docker driver (required for GPU image)',
              default=False)
@click.option('--extra-docker-args',
              help='Extra arguments pass to docker run command')
@click_log.simple_verbosity_option(logger)
def test(dockerfile_or_tag, use_nvidia_driver, extra_docker_args):
    if ':' in dockerfile_or_tag:
        image_tag = dockerfile_or_tag
        dockerfile_path = gen_dockerfile_path_from_tag(image_tag)
    else:
        image_tag = assert_image_tag_from_dockerfile(logger, dockerfile_or_tag)
        dockerfile_path = dockerfile_or_tag

    matrix_yml_path = find_matrix_from_dockerfile(dockerfile_path)
    project_dir = os.path.dirname(matrix_yml_path)

    if not os.path.exists(matrix_yml_path):
        logger.error('matrix.yml not found in project dir: %s', project_dir)
        sys.exit(1)

    extra_args = []
    if use_nvidia_driver or 'gpu' in image_tag:
        try:
            conn = httplib.HTTPConnection('localhost:3476')
            conn.request('GET', '/v1.0/docker/cli')
            data = conn.getresponse().read()
            conn.close()
            extra_args += data.split(' ')
        except:
            # nvidia-docker2
            extra_args.append('--runtime=nvidia')

    if extra_docker_args:
        extra_args += extra_docker_args.split(' ')

    # switch to project dir where matrix.yml is located, we assume test files
    # are located relative matrix.yml
    os.chdir(project_dir)

    with open(matrix_yml_path) as matrix_fobj:
        matrix = yaml.load(matrix_fobj)

    target, env = gen_target_env_from_tag(image_tag)
    if target not in matrix:
        logger.error('target %s not found in matrix.', target)
        sys.exit(1)

    # look up target config
    target_cfg = matrix[target]
    target_cfg_items = gen_target_cfg_items(target_cfg)
    if not target_cfg_items:
        logger.error('Invalid type (%s) for target configuration.',
                     type(target_cfg))
        sys.exit(1)

    env_cfg = None
    for target_env, target_env_cfg in gen_target_env_cfg(target_cfg_items):
        if target_env == env:
            env_cfg = target_env_cfg
            break

    if not env_cfg:
        logger.error('env %s not found in target %s', env, target)
        sys.exit(1)

    test_script = env_cfg.get('_test')
    if not test_script:
        logger.info('No test found for image %s, skipped.', dockerfile)
        sys.exit(0)

    if isinstance(test_script, str):
        test_script = [test_script]

    for script in test_script:
        script = os.path.abspath(script)
        if not os.path.exists(script):
            logger.info('Defined test script (%s) not found for image %s.',
                        script, image_tag)
            sys.exit(1)

        logger.info('--------------------------------------------')
        logger.info('[*] Testing image %s with script %s...',
                    image_tag, script)
        logger.info('--------------------------------------------')

        # Spin up a docker container to test the given image. Here, we mount the
        # directory where the test files live into /build_test path inside the
        # container (-v) so the container has access to all test files
        cmds = ['docker', 'run', '--rm',
                '-v', '%s:/build_test' % os.path.dirname(script)]
        cmds += extra_args
        cmds += [image_tag,
                 'bash', '-c',
                 'cd /build_test && bash %s' % os.path.basename(script)]
        logger.info('running test docker command: %s', cmds)
        check_call(cmds)
