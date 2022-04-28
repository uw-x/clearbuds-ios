# ClearBuds: Wireless Binaural Earbuds for Learning-based Speech Enhancement

## Abstract
We present ClearBuds, the first  end-to-end hardware and software system that utilizes a neural network to enhance speech streamed from two wireless earbuds. Real-time speech enhancement for wireless earbuds  requires high-quality sound separation and background  cancellation, operating in real-time and on a mobile phone.  ClearBuds bridges state-of-the-art deep learning for blind audio source separation and in-ear mobile systems by making two key technical  contributions: 1) a new wireless earbud design capable of operating as a synchronized, binaural microphone array, and 2) a lightweight dual-channel speech enhancement neural network that runs on a mobile device. Results show that our wireless earbuds  achieve a  synchronization error less than 64 us and
our network has a runtime of 21.4 ms on an accompanying mobile phone. In-the-wild evaluation with eight users in  previously unseen indoor and outdoor multipath scenarios demonstrates that our neural network generalizes to learn both spatial and acoustic cues to  perform noise suppression and background speech removal. In a  user-study with 37 participants  who spent over 15.4  hours rating  1041   audio samples collected in-the-wild, our system achieves improved mean opinion score and background   noise  suppression.

## iOS Setup
1. Download and install xcode
2. Open shio-dc.xcworkspace
3. Build and run on your iOS device (Note: You may need to change the bundle identifier)
