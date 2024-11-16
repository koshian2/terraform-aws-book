from torchvision import models

# 事前学習済みのResNet-50モデルをロード
model = models.resnet50(pretrained=True)