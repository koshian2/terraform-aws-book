import gradio as gr
import torch
from torchvision import models
from torchvision.models import ResNet50_Weights
from torchvision import transforms
import requests
import json

from fastapi import FastAPI
import uvicorn

# 事前学習済みのResNet-50モデルをロード（新API）
model = models.resnet50(weights=ResNet50_Weights.DEFAULT)
model.eval()

# クラスラベルのロード（ImageNet）
LABELS_URL = "https://raw.githubusercontent.com/anishathalye/imagenet-simple-labels/master/imagenet-simple-labels.json"
labels = json.loads(requests.get(LABELS_URL).text)

# 画像の前処理
def preprocess(image):
    preprocess_transform = transforms.Compose([
        transforms.Resize(256),
        transforms.CenterCrop(224),
        transforms.ToTensor(),
        transforms.Normalize(
            mean=[0.485, 0.456, 0.406],
            std=[0.229, 0.224, 0.225]
        )
    ])
    return preprocess_transform(image).unsqueeze(0)

# 予測関数
def classify_image(image):
    input_tensor = preprocess(image)
    with torch.no_grad():
        outputs = model(input_tensor)
    probabilities = torch.nn.functional.softmax(outputs[0], dim=0)
    top5_prob, top5_catid = torch.topk(probabilities, 5)
    results = {}
    for i in range(top5_prob.size(0)):
        results[labels[top5_catid[i]]] = float(top5_prob[i].item())
    return results

iface = gr.Interface(
    fn=classify_image,
    inputs=gr.Image(type="pil"),
    outputs=gr.Label(num_top_classes=5),
    title="画像分類アプリケーション",
    description="事前学習済みのResNet-50モデルを使用して、アップロードした画像を分類します。"
)

# --- FastAPI 側でヘルスチェック追加 ---
app = FastAPI()

@app.get("/healthz")
def healthz():
    # 依存リソースの簡易チェックを入れたければここで行う（例: モデル読み込み済みかなど）
    return {"status": "ok"}

# Gradioを "/" にマウント（UIは "/", ヘルスチェックは "/healthz"）
app = gr.mount_gradio_app(app, iface, path="/")

if __name__ == "__main__":
    # ALB などのヘルスチェック用に 0.0.0.0:80 で待受
    uvicorn.run(app, host="0.0.0.0", port=80)
