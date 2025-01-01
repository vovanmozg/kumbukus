# Linux Tools

## Env
Tools can use some ENV vars. Installing some tool can require .env file. .env file placed in separated repository and can be installed with install script. To install, run the following command in your terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/vovanmozg/linuxtools/main/installenv)
```

## Notes

- The script is designed to work with repositories that include a `.env` file. If the file is missing, the installation will fail with an error.
- Make sure `git` is installed before running the script.
