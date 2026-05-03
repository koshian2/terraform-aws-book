from torchvision import models

# 事前学習済みのResNet-50モデルをロード / Load pretrained ResNet-50 model
model = models.resnet50(pretrained=True)