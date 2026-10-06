This project is to test the latest Apple's Foundation Model - AFM 3 Core Advanced performance.

AFM 3 Core Advanced is Apple's flagship 20-billion-parameter, natively multimodal on-device foundation model introduced as part of the third-generation Apple Foundation Models (AFM).

• Parameter Size: 20 billion total parameters.
• Sparse Architecture: Uses Apple's proprietary Instruction-Following Pruning (IFP) technique, activating only 1 to 4 billion parameters per prompt depending on the task's complexity.
• Memory & Storage Strategy: Instead of loading all weights into active RAM (DRAM), the full model resides in flash memory (NAND), swapping only the required active experts into DRAM during inference.

When implementing the code, assume that this demo app will run on the AFM 3 Core Advanced model by default. There’s no need to handle performance limitations of previous-generation models.