/**********
Copyright (c) 2016, Xilinx, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**********/

/*******************************************************************************

SDx Key Concept :
    
    This is a CNN (Convolutional Neural Network) convolutional layer based
    example to showcase the effectiveness of using multiple compute units when
    the base algorithm consists of multiple nested loops with large loop count.   
    The main aim of this example is to help developer to overcome clock
    frequency issues & achieve better performance.

*******************************************************************************/

/*

Kernel Description (Bad Example) :
   
    This example performs CNN (Convolutional Neural Network) convolution
    operation of given input image and weight matrix. This example showcases the
    ineffectiveness of using large local buffers for computation
    (Note : In general local buffers are advised as it reduces DDR to kernel
    transactions). This example has a deep nested loop structure with large loop
    count. 
        
    Note :  
            
            This is the naive version (Bad Example) convolution kernel.
            Good example can be found in source directory "cnn_convolution.cl"

    Arguments :
    
        int *image    (input ) --> Input Image 
        int *weight   (input ) --> Input Weights 
        int *out      (output) --> Output Filters/Images
        int  size     (input ) --> Output Size

    Kernel Configuration :
        
        1. Output Filters  = 256 (Size = 27 x 27) 
        2. Work Groups     = 1
        3. Work Items      = 1     ( One per each Work_Group )
	
        -----------------------------------------------------
        | Parameter     | Value |   Description             |
        -----------------------------------------------------
        | Channels      | 96    | #Input Channels           |                            
        -----------------------------------------------------
        | IHeight       | 27    | Input Image Height        |
        -----------------------------------------------------
        | IWidth        | 27    | Input Image Width         |
        -----------------------------------------------------
        | Window        | 5     | Convolution Window Size   |
        -----------------------------------------------------
        | Stride        | 1     | Convolution Stride        |
        -----------------------------------------------------
        | Padding       | 2     | Convolution Image Padding |
        -----------------------------------------------------
        | OutputFilters | 256   | Output Filters/Images     |
        -----------------------------------------------------
        | OHeight       | 27    | Output Image Height       |
        -----------------------------------------------------
        | OWidth        | 27    | Output Image Width        |
        -----------------------------------------------------


    Memory Usage (Local Buffer (Per Work_Group / Compute Unit)):
        
        1. Image    ~ (IHeight x IWidth x Channels):[274 KB]
        2. Weights  ~ (OutputFilters x Channels x Window x Window):[2400 KB] 
        3. Output   ~ (OutputFilters x OHeight x OWidth):[729 KB]

    Reference : 
             
        To understand Convolution Layer of a CNN better please refer to
        website below (Convolution Demo Animation in the link).
                                                     
        Link: http://cs231n.github.io/convolutional-networks/

*/
#include "defns.h"

__kernel __attribute__ ((reqd_work_group_size(1, 1, 1)))
void cnn(
        const __global int *image,      // Read-Only Image 
        const __global int *weights,    // Read-Only Weight Matrix
        __global int *out,              // Output Filters/Images
        int size,                       // Size of Output Data
        int i_chan,                     // Input Channels
        int o_chan                      // Output Channels
    )
{
    // Local buffer to hold image, weight & output
    int img_lcl[IChan * ISize * ISize];
    int out_lcl[OChan * OSize * OSize];
    int wgt_lcl[WOutChan * WInChan * WSize * WSize];
    
    // Burst Read Image
    __attribute__((xcl_pipeline_loop))
    readImg: for(int i = 0; i < i_chan * ISize * ISize; i++){
        img_lcl[i] = image[i];
    }
    
    // Burst Read Weights
    __attribute__((xcl_pipeline_loop))
    readWt: for(int i = 0; i < o_chan * WInChan * WSize * WSize; i++){
        wgt_lcl[i] = weights[i];
    }
    
    // Runs over output filters
    outputLoop: for(int output = 0, count = 0; output < o_chan; output++) {
        // Runs over Y-Axis of output filter
        outYAxis: for(int y = 0; y < OSize; y++) {
            // Runs over X-Axis of output filter
            outXAxis: for(int x = 0; x < OSize; x++) {
                short acc = 0;
                // Runs over input channel
                convInchan: for(int input = 0; input < i_chan; input++) {
                    // Runs over filter window in Y-direction
                    convILoop: for(int i = 0; i < WSize; i++) {
                        // Runs over filter windows in X-direction
                        __attribute__((xcl_pipeline_loop))
                        convJLoop: for(int j = 0; j < WSize; j++) {
                            // Calculates padding boundaries in X & Y direction
                            int xVal = x*Stride + j-Padding, yVal = y*Stride + i-Padding;
                            
                            if(yVal >= 0 && yVal < ISize && xVal >= 0 && xVal < ISize) {
                                acc +=	(short) img_lcl[(input*ISize + yVal)*ISize + xVal] * 
                                        (short) wgt_lcl[((output*i_chan + input)*WSize + i)*WSize + j];
                            }
                        }
                    }
                }
                
                // Updates local output buffer
                out_lcl[count++] = acc;
            }
        }
    }
    
    // Burst write output
    __attribute__((xcl_pipeline_loop))
    writeOut: for(int i = 0; i < o_chan * OSize * OSize; i++) {
        out[i] = out_lcl[i];
    }

    return;
}
