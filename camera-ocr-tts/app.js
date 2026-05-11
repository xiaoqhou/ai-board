const video = document.getElementById('video');
const canvas = document.getElementById('canvas');
const captureBtn = document.getElementById('capture-btn');
const switchCameraBtn = document.getElementById('switch-camera-btn');
const resultSection = document.getElementById('result-section');
const ocrText = document.getElementById('ocr-text');
const speakBtn = document.getElementById('speak-btn');
const stopBtn = document.getElementById('stop-btn');
const rateInput = document.getElementById('rate');
const pitchInput = document.getElementById('pitch');
const rateValue = document.getElementById('rate-value');
const pitchValue = document.getElementById('pitch-value');
const loadingOverlay = document.getElementById('loading-overlay');
const loadingText = document.getElementById('loading-text');
const errorToast = document.getElementById('error-toast');

let currentStream = null;
let facingMode = 'environment';
let synth = window.speechSynthesis;
let utterance = null;

async function startCamera(facing = 'environment') {
  if (currentStream) {
    currentStream.getTracks().forEach(t => t.stop());
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: facing, width: { ideal: 1920 }, height: { ideal: 1080 } },
      audio: false,
    });
    video.srcObject = stream;
    currentStream = stream;
  } catch (err) {
    showError('Camera access denied. Please grant camera permission.');
  }
}

function showLoading(msg) {
  loadingText.textContent = msg;
  loadingOverlay.hidden = false;
}

function hideLoading() {
  loadingOverlay.hidden = true;
}

function showError(msg) {
  errorToast.textContent = msg;
  errorToast.hidden = false;
  setTimeout(() => { errorToast.hidden = true; }, 4000);
}

async function captureAndOCR() {
  showLoading('Capturing image...');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(video, 0, 0);

  try {
    showLoading('Running OCR...');
    const { data } = await Tesseract.recognize(canvas, 'eng', {
      logger: (m) => {
        if (m.status === 'recognizing text') {
          loadingText.textContent = `OCR: ${Math.round(m.progress * 100)}%`;
        }
      },
    });

    const text = data.text.trim();
    if (!text) {
      showError('No text found. Try again.');
      hideLoading();
      return;
    }

    ocrText.textContent = text;
    resultSection.hidden = false;
    hideLoading();
  } catch (err) {
    hideLoading();
    showError('OCR failed. Please try again.');
  }
}

function speak() {
  if (synth.speaking) synth.cancel();
  const text = ocrText.textContent;
  if (!text) return;
  utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = parseFloat(rateInput.value);
  utterance.pitch = parseFloat(pitchInput.value);
  synth.speak(utterance);
}

function stopSpeech() {
  if (synth.speaking) synth.cancel();
}

captureBtn.addEventListener('click', captureAndOCR);
speakBtn.addEventListener('click', speak);
stopBtn.addEventListener('click', stopSpeech);

rateInput.addEventListener('input', () => {
  rateValue.textContent = rateInput.value;
  if (synth.speaking) speak();
});
pitchInput.addEventListener('input', () => {
  pitchValue.textContent = pitchInput.value;
  if (synth.speaking) speak();
});

switchCameraBtn.addEventListener('click', () => {
  facingMode = facingMode === 'environment' ? 'user' : 'environment';
  startCamera(facingMode);
});

startCamera(facingMode);
