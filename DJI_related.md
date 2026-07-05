# 大疆模块相关

## 直通给 WSL 的方法

安装 usbipd

```
winget install --interactive --exact dorssel.usbipd-win
```

列出设备

```
usbipd list
```

绑定设备

```
usbipd bind --busid <BUSID>
```

一般来说，绑定设备只需要做一次，但实际上公对公插头的方向调换一下会导致 ID 变化一次。最后至少会需要绑两个 ID。

首先启动 WSL，然后附加到 WSL

```
usbipd attach --wsl --busid <BUSID>
```

在 WSL 中验证

```
lsusb
```

解除附加

```
usbipd detach -a
```

## 魔改模块

**以下来自 VoHive 作者：**

大疆的4G模块(1代)硬件性价比高(价格在30-40不等,之前还有25的),并有精美的外观(这点EC20裸板没法比的)，
但其默认的USB VID/PID是大疆私有的，导致通用的linux驱动无法直接识别。
当本质它是移远EG25G核心,通过修改其内部参数，可以将其修改成经典的移远（Quectel）EC20/EC25模块，从而无缝接入vohive短信及网络管理平台。

经测试大疆4G模块(1代)完美支持电信volte,完美支持vohive

一、 修改大疆模块设备ID（修改为移远EC20/EC25）

在linux系统未插其他干扰模块的情况下，请确保已安装 `socat` 工具（用于发送AT指令）：

```
sudo apt-get update && sudo apt-get install socat -y
```

接着依次执行以下命令，将大疆模块修改为移远EC20/EC25身份：

```
# 1. 临时加载 option 驱动模块
sudo modprobe option

# 2. 将大疆模块当前的识别码（2ca3:4006）写入 option 驱动，使其生成串口文件
sudo echo 2ca3 4006 | sudo tee /sys/bus/usb-serial/drivers/option1/new_id

# 3. 通过生成的 /dev/ttyUSB2 端口发送AT指令，将USB参数永久修改为移远格式（2C7C:0125）
sudo echo 'AT+QCFG="usbcfg",0x2C7C,0x0125,1,1,1,1,1,0,0' | sudo socat - /dev/ttyUSB2,crnl

# 4. 重启模块使配置生效
sudo echo 'AT+CFUN=1,1' | sudo socat - /dev/ttyUSB2,crnl
```

执行完软重启命令后，模块会重新初始化。等待一小会可以在终端输入 `lsusb` 命令查看，设备应该已经成功显示为 `2c7c:0125 Quectel Wireless Solutions Co., Ltd. EC25 LTE modem`。

二、 一键安装部署vohive平台

模块伪装完成后，就可以使用vohive官方提供的一键脚本在Linux系统上进行部署。

执行以下命令进行一键安装：

```
wget -O - https://raw.githubusercontent.com/iniwex5/vohive-release/master/install.sh | sh
```

部署说明：

默认安装路径：

- 二进制文件：`/opt/vohive/bin/vohive`
- 配置文件：`/opt/vohive/config/config.yaml`
- 数据与日志：`/opt/vohive/data` 和 `/opt/vohive/logs`

管理平台访问：
安装完成后，在浏览器输入 `http://你的设备IP:7575` 即可进入vohive后台。默认的用户名和密码为 `admin / admin`（建议登录后立即修改）。

### 个人补充

建议先在完整的 Linux 虚拟机中写好模块，然后拔插后附加到 WSL 中使用。
