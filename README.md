# Kumbukus

### Using install

Use `install` to download scripts:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installapps)
```

It clones the repository and lets you select which scripts to install in your `~/bin` folder.

### configs

Use `installconfigs` to install additional configs:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installconfigs)
```

## Env

Tools can use some ENV vars. Installing some tool can require .env file. .env file placed in separated repository and can be installed with install script. To install, run the following command in your terminal:

### Using installenv

Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installenv) <repository_url>
```

where <repository_url> is repo containing .env file.

This fetches the `.env` file from <repository_url> and places it in the project or your `.config` folder, depending on your setup.

## Notes

After installing the script, add the following line to your `~/.zshrc` to source the configuration:

```bash
source ~/.kumbukus/config
```
