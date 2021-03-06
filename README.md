# Testing `lightgbm.dask`

[![GitHub Actions status](https://github.com/jameslamb/lightgbm-dask-testing/workflows/Continuous%20Integration/badge.svg?branch=main)](https://github.com/jameslamb/lightgbm-dask-testing/actions)

This repository can be used to test and develop changes to LightGBM's Dask integration. It contains the following useful features:

* `make` recipes for building a local development image with `lightgbm` installed from a local copy, and Jupyter Lab running for interactive development
* Jupyter notebooks for testing `lightgbm.dask` against a `LocalCluster` (multi-worker, single-machine) and a `dask_cloudprovider.aws.FargateCluster` (multi-worker, multi-machine)
* `make` recipes for publishing a custom container image to ECR Public repository, for use with AWS Fargate

<hr>

## Getting Started

To begin, clone a copy of LightGBM to a folder `LightGBM` at the root of this repo. You can do this however you want, for example:

```shell
git clone --recursive git@github.com:microsoft/LightGBM.git LightGBM
```

If you're developing a reproducible example for [an issue](https://github.com/microsoft/LightGBM/issues) or you're testing a potential [pull request](https://github.com/microsoft/LightGBM/pulls), you probably want to clone LightGBM from your fork, instead of the main repo.

<hr>

## Develop in Jupyter

This section describes how to test a version of LightGBM in Jupyter.

#### 1. Set `IMAGE_NAME` in `image.env` to something random.

I like to do this by generating a UUID.

```shell
python -c "import uuid; print(str(uuid.uuid4()))"
```

Open `image.env`, and replace the existing value of `IMAGE_NAME` with one that ends with that UUID. This will be used to control the image tags used in later steps, and you want it to be totally unique to you.

#### 2. Build the base image

Some dependencies needed to test LightGBM aren't going to change over the course of your development...things like `cmake` and `scikit-learn`. So these should be installed one time in a base image.

```shell
make base-image
```

This base image is based on https://github.com/dask/dask-docker/tree/master/notebook.

You'll probably only need to run this once during development.

#### 3. Build the notebook image

The notebook image is built from the base image, but it has your local copy of `LightGBM/` installed inside it. You'll probably rebuild this image many times during development, as you test your changes.

```shell
make notebook-image
```

#### 4. Run a notebook locally

Start up Jupyter Lab! This command will run Jupyter Lab in a container using the image you built with `make notebook-image`.

```shell
make start-notebook
```

After running this command, you'll see some output like this:

```text
[C 23:03:44.234 LabApp]
    To access the notebook, open this file in a browser:
        file:///home/jovyan/.local/share/jupyter/runtime/nbserver-19-open.html
    Or copy and paste one of these URLs:
        http://d96d64837199:8888/?token=e8aa897c8afbbbc559976854a78cc9effe957a912270f7bf
     or http://127.0.0.1:8888/?token=e8aa897c8afbbbc559976854a78cc9effe957a912270f7bf
```

Copy the URL starting with `http://127.0.0.1` and paste it into your web browser. This will open Jupyter Lab.

The command `make start-notebook` mounts your current working directory into the running container. That means that even though Jupyter Lab is running inside the container, changes that you make in it will be saved on your local filesystem even after you shut the container down. So you can edit and create notebooks and other code in there with confidence!

When you're done with the notebook, stop the container by running the following from another shell:

```shell
make stop-notebook
```

<hr>

## Test with a `LocalCluster`

To test `lightgbm.dask` on a `LocalCluster`, run the steps in ["Develop in Jupyter"](#develop-in-jupyter), then try out [`local.ipynb`](./notebooks/local-cluster.ipynb) or your own notebooks.

<hr>

## Test with a `FargateCluster`

There are some problems with Dask code which only arise in a truly distributed, multi-machine setup. To test for these sorts of issues, I like to use [`dask-cloudprovider`](https://github.com/dask/dask-cloudprovider).

The steps below describe how to test a local copy of LightGBM on a `FargateCluster` from `dask-cloudprovider`.

#### 1. Build the cluster image

Build an image that can be used for the scheduler and works in the Dask cluster you'll create on AWS Fargate. This image will have your local copy of LightGBM installed in it.

```shell
make cluster-image
```

#### 2. Install and configure the AWS CLI

For the rest of the steps in this section, you'll need access to AWS resources. To begin, install the AWS CLI if you don't already have it.

```shell
pip install --upgrade awscli
```

Next, configure your shell to make authenticated requests to AWS. If you've never done this, you can see [the AWS CLI docs](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

The rest of this section assums that the shell variables `AWS_SECRET_ACCESS_KEY`, `AWS_ACCESS_KEY_ID`, and `AWS_DEFAULT_REGION` have been set.

I like to set these by keeping them in a file

```text
# file: aws.env
AWS_SECRET_ACCESS_KEY=your-key-here
AWS_ACCESS_KEY_ID=your-access-key-id-here
AWS_DEFAULT_REGION=us-east-1
```

and then sourcing that file

```shell
set -o allexport
source aws.env
set +o allexport
```

#### 3. Push the cluster image to ECR

To use the cluster image in the containers you spin up on Fargate, it has to be available in a container registry. This project uses the free AWS Elastic Container Registry (ECR) Public. For more information on ECR Public, see [the AWS docs](https://docs.amazonaws.cn/en_us/AmazonECR/latest/public/docker-push-ecr-image.html).

The command below will create a new repository on ECR Public, store the details of that repository in a file `ecr-details.json`, and push the cluster image to it. The cluster image will not contain your credentials, notebooks, or other local files.

```shell
make push-image
```

This may take a few minutes to complete.

#### 4. Run the AWS notebook

Follow the steps in ["Develop in Jupyter"](#develop-in-jupyter) to get a local Jupyter Lab running. Open [`aws.ipynb`](./notebooks/fargate-cluster.ipynb). That notebook contains sample code that uses `dask-cloudprovider` to provision a Dask cluster on AWS Fargate.

You can view the cluster's current state and its logs by navigating to the Elastic Container Service (ECS) section of the AWS console.

#### 5. Clean Up

As you work on whatever experiment you're doing, you'll probably find yourself wanting to repeat these steps multiple times.

To remove the image you pushed to ECR Public and the repository you created there, run the following

```shell
make delete-repo
```

Then, repeat the steps above to rebuild your images and test again.

<hr>

## Useful Links

* https://github.com/microsoft/LightGBM/pull/3515
* https://docs.aws.amazon.com/cli/latest/reference/ecr-public/
* https://docs.amazonaws.cn/en_us/AmazonECR/latest/public/docker-push-ecr-image.html
* https://github.com/dask/dask-docker
* https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
