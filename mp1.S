# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64


# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
		# Setting up the stack frame
		pushl		%ebp
		movl		%esp, %ebp

		# Protect the callee-saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Loading in the parameter arg
		movl		8(%ebp), %ebx

		# Check if there are missiles left in the linked list
		cmpl		$0, mp1_missile_list
		je		missiles_update_complete

		# Call the first function to update/check missiles
		# Save the caller-saved registers
		pushl		%eax
		pushl		%ecx
		pushl		%edx
		call		update_missiles
		popl		%edx
		popl		%ecx
		popl		%eax
		
		# No missiles left or all updates are completed
		missiles_update_complete:
		popl		%edx
		popl		%ecx
		popl		%eax
		
		#
		pushl		%eax
		pushl		%ecx
		pushl		%edx
		
		call		update_cities

		popl		%edx
		popl		%ecx
		popl		%eax

		pushl		%eax
		pushl		%ecx
		pushl		%edx
		
		call		redraw_crosshairs
		
		popl		%edx
		popl		%ecx
		popl		%eax

		popl		%edi
		popl		%esi
		popl		%ebx
		
		leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
		movl		8(%esp), %eax
		cmpl		$4, %eax
		jg		invalid_cmd
		cmpl		$0, %eax
		jl		invalid_cmd
		jmp		*jumptable(,%eax,4)

invalid_cmd:
		movl		$-1, %eax
		ret

jumptable:
		.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------

update_missiles:
		pushl		%ebp
		movl		%esp, %ebp

		# Protect the callee-saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi
		
		# Load in the missile list
		movl		mp1_missile_list, %ebx

		# Go over the missile linked list
		missile_loop_check:
		# Check if the curr points to NULL
		cmpl		$0, %ebx
		je		end_of_missile_list

		# Check if the missile is exploding
		cmpl		$0, EXPLODED(%ebx)
		jne		exploding

		# Store each piece of data into different registers
		movl		X(%ebx), %ecx
		movl		Y(%ebx), %edx
		movl		X(%ebx), %eax
		movl		Y(%ebx), %esi
		roll		$16, %eax
		roll		$16, %esi
		andl		$0x0000ffff, %eax
		andl		$0x0000ffff, %esi

		# Case 1, check if the missile has moved off the screen
		cmpw		$0, %cx
		jl		missile_remove
		cmpw		$79, %cx
		jg		missile_remove
		cmpw		$0, %dx
		jl		missile_remove
		cmpw		$24, %dx
		jg		missile_remove
		
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		movb		C(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		# Case 2, check if the missile has reached destination
		reached_destination_check:
		movl		DEST_X(%ebx), %ecx
		movl		DEST_Y(%ebx), %edx
		cmpw		%cx, %ax
		jne		position_change
		cmpw		%dx, %si
		jne		position_change	

		exploding:
		pushl		%ebx
		call		missile_explode
		popl		%ebx
		subl		$1, EXPLODED(%ebx)
		cmpl		$0, EXPLODED(%ebx)
		je		missile_remove
		jmp		next_missile_in_the_list

		missile_remove:
		pushl		%ebx
		call		mp1_missile_remove
		popl		%ebx
		jmp		next_missile_in_the_list
		
		# 3rd function, redraw missiles in new position
		position_change:
		movl		X(%ebx), %eax
		movl		Y(%ebx), %esi
		roll		$16, %eax
		roll		$16, %esi
		andl		$0x0000ffff, %eax
		andl		$0x0000ffff, %esi
		imull		$2, %eax
		imull		$160, %esi

		# Replace the missile at old position with space char
		addl		%esi, %eax
		movb		$32, %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		
		# Calculate the new position
		pushl       %edi
		movl        X(%ebx), %edi
		addl		VX(%ebx), %edi
		movl        %edi, X(%ebx)
		movl        Y(%ebx), %edi
		addl		VY(%ebx), %edi
		movl        %edi, Y(%ebx)
		popl        %edi

		movl		X(%ebx), %eax
		movl		Y(%ebx), %esi
		roll		$16, %eax		
		roll		$16, %esi
		andl		$0x0000ffff, %eax
		andl		$0x0000ffff, %esi
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		movb		C(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		jmp		next_missile_in_the_list

		next_missile_in_the_list:
		movl		%ebx, %ecx
		movl		NEXT(%ecx), %ebx
		jmp		missile_loop_check		

		end_of_missile_list:
		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

mp1_missile_remove:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
	
		# Protect the callee save registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		movl		mp1_missile_list, %esi

		missile_head_check:
		cmpl		$0, %esi
		je		missile_removal_complete
		cmpl		%esi, %ebx
		je		head_deletion
		
		# Track the element prior to the element being removed
		missile_list_loop:
		cmpl		$0, %esi
		je		missile_removal_complete
		cmpl		NEXT(%esi), %ebx
		je		element_deletion
		movl		NEXT(%esi), %esi
		jmp		missile_list_loop
		
		element_deletion:
		movl		NEXT(%ebx), %edi
		# Protect the caller save register
		pushl		%eax
		# Push the arg to mp1_free
		pushl		%ebx
		call		mp1_free
		popl		%ebx
		popl		%eax
		movl		%edi, NEXT(%esi)
		jmp		missile_removal_completed

		head_deletion:
		# Protect the caller save register
		pushl		%eax
		# Push the arg to mp1_free
		pushl		%ebx
		call		mp1_free
		popl		%ebx
		popl		%eax
		movl		%esi, mp1_missile_list
	
		missile_removal_completed:
		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

update_cities:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Offset = 160 * 24 + 2 * 18 = 3876
		update_first_city:
		movl		$3876, %eax
		cmpb		$0, base_alive
		je		destroy_first_city
		pushl		%eax
		call		redraw_city
		popl		%eax
		jmp		update_second_city
		destroy_first_city:
		pushl		%eax
		call		draw_destroyed_city		
		popl		%eax

		# Offset = 160 * 24 + 2 * 38 = 3916
		update_second_city:
		movl		$3916, %eax
		cmpb		$0, 1(base_alive)
		je		destroy_second_city
		pushl		%eax
		call		redraw_city
		popl		%eax
		jmp		update_third_city
		destroy_second_city:
		pushl		%eax
		call		draw_destroyed_city
		popl		%eax

		# Offset = 160 * 24 + 2 * 58 = 3956
		update_third_city:
		movl		$3956, %eax
		cmpb		$0, 2(base_alive)
		je		destroy_third_city
		pushl		%eax
		call		redraw_city
		popl		%eax
		jmp		update_cities_completed
		destroy_third_city:
		pushl		%eax
		call		draw_destroyed_city
		popl		%eax
		
		update_cities_completed:
		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

redraw_city:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		movl		$base_pic, %ebx
		movb		0(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		addl		$2, %eax
		movb		1(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		2(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		3(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		4(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

draw_destroyed_city:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		movl		$dead_base_pic, %ebx
		movb		0(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		addl		$2, %eax
		movb		1(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		2(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		3(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		addl		$2, %eax
		movb		4(%ebx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

redraw_crosshairs:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi
		
		# Calculate the offset (2 * x + 80 * y) * 2
		movl		crosshairs_x, %eax
		movl		crosshairs_y, %ebx
		imull		$2, %eax
		imull		$160, %ebx

		# Replace anything at assigned screen position with "+"
		addl		%ebx, %eax
		movb		$43, %cl
		call		mp1_poke

		# Restore the stack frame
		popl		%ebx
		popl		%esi
		popl		%edi
		leave
		ret

mp1_ioctl_startgame:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Initialize all the globally defined variables
		movl		$0, mp1_missile_list
		# 0, 1, 1, 1 because x86 stores from the leftmost byte
		# 0 is padding
		movl		$base_alive, %ebx
		movb		$1, %ebx
		movb		$1, 1(%ebx)
		movb		$1, 2(%ebx)
		movb		$0, 3(%ebx)

		# Initialize mp1_score to 0
		movl		$0, mp1_score

		# Initialize the crosshairs to (40, 12)
		movl		$40, crosshairs_x
		movl		$12, crosshairs_y

		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

mp1_ioctl_addmissile:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Fetch the input parameter arg
		movl		8(%ebp), %ebx

		# 1 pointer + 8 * 4 parameters = 1 + 32 = 33 bytes
		movl		$33, %ecx
		pushl		%ecx
		call		mp1_malloc
		popl		%ecx

		# %eax has the dynamically allocated address from malloc
		pushl		%ecx
		pushl		%ebx	
		pushl		%eax
		call		mp1_copy_from_user
		cmpl		$0, %eax
		jne		add_fail
		popl		%eax
		popl		%ebx
		popl		%ecx

		pushl		%edx
		movl		mp1_missile_list, %edx
		movl		%edx, NEXT(%eax)
		movl		%eax, mp1_missile_list
		popl		%edx

		# Return 0 if add missile succeeded
		movl		$0, %eax

		# Restore stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

		add_fail:
		popl		%eax
		popl		%ebx
		popl		%ecx

		# Free the dynamically allocated memory (address in eax)
		pushl		%eax
		call		mp1_free
		popl		%eax
		
		# Return -1 if add missile failed
		movl		$-1, %eax

		# Restore stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

mp1_ioctl_movexhairs:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Save the registers that would be potentially used
		pushl		%eax
		pushl		%ecx
		pushl		%edx
		
		# Check if there is a change to the crosshairs position
		movl		8(%ebp), %ebx
		cmpl		$0, %ebx
		# If none, leave with nothing changed
		je		crosshairs_change_completed

		# Fetch the input arg
		movl		%ebx, %esi
		# Rotate by 16 bits so the upper bits become the lower
		roll		$16, %esi

		# Replace the crosshair at old position to be blank
		movl		crosshairs_x, %eax
		movl		crosshairs_y, %ecx
		# Calculating offsets: x=(columns)*2 and y=(rows)*80*2
		imull		$2, %eax
		imull		$160, %ecx
		addl		%ecx, %eax
		movb		$32, %cl
		call		mp1_poke

		# Adding the offsets
		addw		%bx, crosshairs_x
		addw		%si, crosshairs_y

		# Conditional Checks (too large or too small)
		check_if_x_too_small:
		cmpl		$0, crosshairs_x
		jg		check_if_x_too_large
		movl		$0, crosshairs_x
		jmp		check_if_y_too_small		

		check_if_x_too_large:
		cmpl		$70, crosshairs_x
		jl		check_if_y_too_small
		movl		$70, crosshairs_x

		check_if_y_too_small:
		cmpl		$0, crosshairs_y
		jg		check_if_y_too_large
		movl		$0, crosshairs_y
		jmp		boundary_check_done

		check_if_y_too_large:
		cmpl		$24, crosshairs_y
		jl		boundary_check_done
		movl		$24, crosshairs_y

		boundary_check_done:
		# Load back the new crosshair values (new or old)
		movl		crosshairs_x, %eax
		movl		crosshairs_y, %ecx

		# Draw a "plus" sign as crosshair at new position
		draw_crosshairs:
		imull		$2, %eax
		imull		$80, %ecx
		addl		%ecx, %eax
		movb		$43, %cl
		call		mp1_poke

		# Restore the stack frame
		crosshairs_change_completed:
		popl		%edx
		popl		%ecx
		popl		%eax
		popl		%edi
		popl		%esi
		popl		%ebx

		# Always return 0
		movl		$0, %eax
		leave		
		ret

mp1_ioctl_getstatus:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Saving registers that might be potentially used
		pushl		%eax
		pushl		%ecx
		pushl		%edx

		# Load in the argument (address of the user space)
		movl		8(%ebp), %ebx

		# Initialize the value passed to the user to 0
		movl		$0, %ecx
		
		pushl       %edx
		movl        $base_alive, %edx
		
		base_3_alive:
		cmpb		$0, 2(%edx)
		je		base_2_alive
		addl		$1, %ecx
		
		base_2_alive:
		shll		$1, %ecx
		cmpb		$0, 1(%edx)
		je		base_1_alive
		addl		$1, %ecx
		
		base_1_alive:
		shll		$1, %ecx
		cmpb		$0, %edx
		je		get_mp1_score
		addl		$1, %ecx

		get_mp1_score:
		shll		$16, %ecx
		movl		mp1_score, %esi
		addw		%si, %cx

		movl		$4, %edi
		# Pushing the parameters for mp1_copy_to_user function
		# mp1_copy_to_user (user address, from address, size)
		pushl		%edi
		pushl		%ecx
		pushl		%ebx
		call		mp1_copy_to_user
		# Cleaning the stack memory pushed for mp1_copy_to_user
		popl		%ebx
		popl		%ecx
		popl		%edi

		# Return value in the eax, if not 0 then copy failed
		cmpl		$0, %eax
		jne		copy_to_user_fail

		# Restore the stack frame pushed for used register
		popl		%edx
		popl		%ecx
		popl		%eax
		
		# Set the return value 0
		movl		$0, %eax

		# Restore stack frame and return		
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

		copy_to_user_fail:
		# Restore the stack frame pushed for used register
		popl		%edx
		popl		%ecx
		popl		%eax
		
		# Set the return value -1
		movl		$-1, %eax

		# Restore stack frame and return		
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

mp1_ioctl_endgame:
		# Set up the stack frame
		pushl		%ebp
		movl		%esp, %ebp
		
		# Protect the callee saved registers
		pushl		%ebx
		pushl		%esi
		pushl		%edi

		# Save registers that would potentially be used
		pushl		%eax
		pushl		%ecx
		pushl		%edx

		# Linked list removal
		# head = head->next
		missile_list_loop_2:
		movl		mp1_missile_list, %ebx
		cmpl		$0, %ebx
		je		end_cleanup
		movl		NEXT(%ebx), %ecx
		movl		%ecx, mp1_missile_list
		pushl		%ebx
		call		mp1_free
		popl		%ebx
		jmp		missile_list_loop_2

		end_cleanup:
		popl		%edx
		popl		%ecx
		popl		%eax
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret
