# Kumbukus

### Using install

Use `install` to download scripts:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installapps)
```

It clones the repository and lets you select which scripts to install in your `~/bin` folder.

You can create your own repository with custom apps and install them using:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installapps) <repository_url>
```

### configs

Use `installconfigs` to install additional configs:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installconfigs)
```

## Env

Tools may use environment variables. Some tools require a `.env` file, which is stored in a separate repository. You can install the `.env` file using the install script.

### Using installenv

Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/kumbukus/main/installenv) <repository_url>
```

Replace `<repository_url>` with the repository containing your `.env` file.

This command fetches the `.env` file from the specified repository and places it in your project or `.config` folder, depending on your setup.

## Notes

After installing the script, add the following line to your `~/.zshrc` to source the configuration:

```bash
source ~/.kumbukus/config
```
