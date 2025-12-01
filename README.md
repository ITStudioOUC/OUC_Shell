<br>
<div align="center">
    <img src="https://vip.123pan.cn/1842292950/ymjew503t0m000d7w32xzgmn6upslg2jDIYxDqi2DqryDcxwDwizAY==.svg" width=100/>
</div>
<div align="center">
    <h1>OUC Shell</h1>
</div>
<br>
<div align="center">
    <img src="https://vip.123pan.cn/1842292950/yk6baz03t0l000d7w33fy0bj9oqjoo4zDIYxDqi2DqryDcxwDwizAY==.svg"/>
    <img src="https://img.shields.io/badge/Language-Shell-green">
    <img src="https://img.shields.io/badge/License-MIT-Black">
</div>
<br>

为方便🐏大学生，爱特工作室编写了一些非常实用的Shell小程序，并且你可以非常方便地通过一个配置文件来启用和配置所有这里有的功能，而且只需要注册一个**Systemd**服务就可以实现自动化流程，非常方便

## ❗ 严正声明

本项目**仅供个人和学习使用**，禁止将本项目的代码作为商业及非法用途，禁止恶意修改本仓库代码，禁止通过本仓库代码挖掘校园网信息系统漏洞，违者将承担法律责任

## 🍕 食用方法

1.克隆本仓库

```
git clone git@github.com:ITStudioOUC/OUC_Shell.git
```

2.运行脚本

```
cd OUC_shell
bash main.sh
```

在首次运行或重新生成配置文件时，脚本会自动生成配置文件 `config.toml` ，之后脚本会自动退出，在你编辑好配置文件后重新启动脚本即可

3.注册服务

创建服务文件

```
touch /etc/systemd/system/oucshell.service
```

编辑服务文件

```
# 这只是一个systemd服务注册示例，不要直接拿来用
[Unit]
Description=Campus Helper Service (Electricity & More)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/path/to/your/repo # 这里改成你克隆的本仓库的路径
ExecStart=/bin/bash /path/to/main.sh # 这里改成你的main.sh的路径
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

4.启动服务和设置自启动

```
systemctl start oucshell.service
systemctl enable oucshell.service
```

## 🤝 贡献者

<!-- readme: contributors -start -->
<table>
	<tbody>
		<tr>
            <td align="center">
                <a href="https://github.com/Yaosanqi137">
                    <img src="https://avatars.githubusercontent.com/u/99163721?v=4" width="100;" alt="Yaosanqi137"/>
                    <br />
                    <sub><b>Yaosanqi137</b></sub>
                </a>
            </td>
		</tr>
	<tbody>
</table>
<!-- readme: contributors -end -->