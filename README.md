# Kdmid bot

With the help of this small bot you can check your appointment at the Russian consulate. This bot works only for old versions of consulates (kdmid.ru). For new ones you can use this [repository](https://github.com/gugglegum/midpass) from [gugglegum](https://github.com/gugglegum). 

This bot was originally developed by [accessd](https://github.com/accessd/). I modified it and added the following:

- A more understandable .env file
- Different captcha handling to reduce errors by 2captcha.com
- Re-passing the captcha in case of errors and reporting these errors to the service to reduce costs.
- Changed parsing conditions of the final page to avoid false positives.
- Added sending photos of the final page to the bot if there is room
- Added sending location to the bot 

## Setup

Register on https://2captcha.com/ and get API key.

Get order id and code from the link http://istanbul.kdmid.ru/queue/OrderInfo.aspx?id=ORDER_ID&cd=CODE

Create .env file and replace variables with your values:

```sh
cp .env.example .env
```

### Docker

```sh
bin/build && bin/start
```

Run bot with:

```sh
bin/bot
```

#### Несколько заявлений

Если у вас несколько заявлений, создайте `.env.<var>` и `compose.<var>.yml` файлы для каждого заявления и запускайте с подключением патча:

```sh
docker compose -f docker-compose.yml -f compose.<var>.yml up bot
```

Либо добавить отдельные сервисы в основной файл.

**How to see the browser?**

View the firefox node via VNC (password: secret):

```sh
open vnc://localhost:5900
```

> **_NOTE:_**  If you want to access VNC via any public network interface you will need to update listening address in `docker-compose.yml` for `node-firefox` service

After testing that bot works properly put command to run bot in crontab, like:

> **WARNING:** Внимание! При повторяющихся запросах к системе в течение дня более 24 раз Ваша заявка будет заблокирована.

```sh
0 12 * * * root cd /path/to/the/bot; bin/bot >> kdmid-bot.log 2>&1
```

Than you can look at the log file by:

```sh
tail -f kdmid-bot.log
```

### Locally

Install ruby 3.1.2 with rbenv for example.

Install browser and driver: http://watir.com/guides/drivers/
You can use firefox with geckodriver.

Setup dependencies:

```sh
bundle
```

Run bot with:

```sh
ruby bot.rb
```

## Issues
- Browser does not close in some occasions. Which may lead to RAM leak and Selenium may start to refuse connections from bot. I'm looking into this but overall I recommend to restart bot containers in docker after 4-5 hours as temporary solution 
