# irr_update

IRR（route / route6 / mntner / aut-num / as-set）オブジェクトのメール自動化ツール

## 主な機能
- 複数レジストリ対応
- 対応オブジェクト: mntner / aut-num / as-set / route / route6
- モード: check / dry-run / production
- objects/*.ini を正とする
- SMTP送信は nc（netcat）を使用
- レジストリ単位の whois 確認

## レジストリ
レジストリ名は以下から動的に解決されます:
  settings/registries/

このディレクトリに存在する任意のレジストリを指定可能です。
小文字の使用を推奨します。

## ディレクトリ構成
/opt/irrv2/
  scripts/
  objects/
  settings/
  logs/
  docs/

## モード

check:
  mail body のみ生成

dry-run:
  --smtp-user 宛にテスト送信
  --no-smtp 時は --mail-sender 宛に送信

production:
  実レジストリへ送信
  確認が必要

## オプション

--registry <registry>
--object <object>
--mode <mode>
--name <name>
--mail-sender <email>
--smtp-user <user>

--objects <list>
  （cron_runner.sh 用）
  カンマ区切り指定

## オブジェクト

aut-num / as-set:
  複数オブジェクト対応
  --nameで単体指定

mntner:
  レジストリ依存

route / route6:
  一括更新対応

## ログ

ログは以下に保存されます:
  logs/scripts/
  logs/registry/<registry>/<object>/

## 補足
- 未指定項目は common.conf から補完
- dry-run でも実際にSMTP通信を行う
- --mail-smtp-user は廃止。--smtp-user に統一
