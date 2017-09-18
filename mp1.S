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
		je			missiles_update_complete

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
		jg			invalid_cmd
		cmpl		$0, %eax
		jl			invalid_cmd
		jmp			*jumptable(,%eax,4)

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
		
		cmpl		$0, mp1_missile_list
		je			end_of_missile_list
		# Load in the missile list
		movl		mp1_missile_list, %edx

		# Go over the missile linked list
		missile_loop_check:
		# Check if the curr points to NULL
		cmpl		$0, %edx
		je			end_of_missile_list

		# Check if the missile is exploding
		cmpl		$0, EXPLODED(%edx)
		jne			is_exploding

		# Store each piece of data into different registers
		movl		X(%edx), %eax
		movl		Y(%edx), %esi
		roll		$16, %eax
		roll		$16, %esi
		andl		$0x0000ffff, %eax
		andl		$0x0000ffff, %esi

		# Case 1, check if the missile has moved off the screen
		off_screen_check:
		cmpl		$0, X(%edx)
		jl			missile_remove
		cmpl		$79, X(%edx)
		jl			missile_remove
		cmpl		$0, Y(%edx)
		jl			missile_remove
		cmpl		$24, Y(%edx)
		jl			missile_remove
		
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		movb		C(%edx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx

		# Case 2, check if the missile has reached destination
		reached_destination_check:
		movl		X(%edx), %eax
		roll		$16, %eax
		andl		$0x0000ffff, %eax
		movl		Y(%edx), %esi
		roll		$16, %esi
		andl		$0x0000ffff, %esi
		
		check_x_destination:
		cmpl		%eax, DEST_X(%edx)
		je			check_y_destination
		jmp			continue_moving
		
		check_y_destination:
		cmpl		%esi, DEST_Y(%edx)
		je			exploding
		jmp			continue_moving
		
		exploding:
		pushl		%edx
		call		missile_explode
		popl		%edx
		
		cmpl		$0, %eax
		je			continue_moving
		
		pushl		%edx
		call		mp1_notify_user
		popl		%edx
		
		continue_moving:
		cmpl		$0, EXPLODED(%edx)
		je			position_change
		subl		$1, EXPLODED(%edx)
		cmpl		$0, EXPLODED(%edx)
		je			missile_remove
		
		# Rotate the upper 16 bits of X and Y to lower
		movl		X(%edx), %eax
		roll		$16, %eax
		andl		$0x0000ffff, %eax
		movl		Y(%edx), %esi
		roll		$16, %esi
		andl		$0x0000ffff, %esi
		
		# Calculate the offset
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		movb		$EXPLOSION, %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		jmp			next_missile_in_the_list
		
		# 3rd function, redraw missiles in new position
		position_change:
		movl		X(%edx), %eax
		movl		Y(%edx), %esi
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
		
		# Add the velocity to the current position and store back
		movl        X(%edx), %eax
		addl		VX(%edx), %eax
		movl        %eax, X(%edx)
		movl        Y(%edx), %esi
		addl		VY(%edx), %esi
		movl        %esi, Y(%edx)
		
		# Rotate the upper 16th bits to lower to calculate offsets
		movl		X(%edx), %eax
		movl		Y(%edx), %esi
		roll		$16, %eax		
		roll		$16, %esi
		andl		$0x0000ffff, %eax
		andl		$0x0000ffff, %esi
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		
		# Push the missile character as the argument to display, and protect %edx
		# Args in %eax and %cl, %edx used as return register
		movb		C(%edx), %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		jmp			next_missile_in_the_list
		
		is_exploding:
		movl		$0, VX(%edx)
		movl		$0, VY(%edx)
		pushl		%edx
		call		missile_explode
		popl		%edx
		cmpl		$0, %eax
		je			no_nearby_explosion
		pushl		%edx
		call		mp1_notify_user
		popl		%edx
		
		no_nearby_explosion:
		subl		$1, EXPLODED(%edx)
		cmpl		$0, EXPLODED(%edx)
		je			missile_remove

		next_missile_in_the_list:
		movl		%edx, %edi
		cmpl		$0, %edx
		je			end_of_missile_list
		movl		NEXT(%edx), %esi
		cmpl		$0, %esi
		je			end_of_missile_list
		movl		%esi, %edx
		jmp			missile_loop_check		

		end_of_missile_list:
		# Restore the stack frame
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

###############################################
		
		
missile_remove:
			
		cmpl		$0, %edx
		je			end_of_missile_list
		# Clear the missile position to be a blank
		movl		X(%edx), %eax
		roll		$16, %eax
		andl		$0x0000ffff, %eax
		movl		Y(%edx), %esi
		roll		$16, %esi
		andl		$0x0000ffff, %esi
		imull		$2, %eax
		imull		$160, %esi
		addl		%esi, %eax
		movb		$32, %cl
		pushl		%edx
		call		mp1_poke
		popl		%edx
		
		# Protect caller-save registers
		pushl		%eax
		pushl		%ecx
		pushl		%edx
		call		mp1_missile_remove
		addl		$4, %esp
		popl		%ecx
		popl		%eax
		jmp			next_missile_in_the_list


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
		je			missile_removal_completed
		cmpl		%esi, %edx
		je			head_deletion
		
		# Track the element prior to the element being removed
		missile_list_loop:
		cmpl		$0, %esi
		je			missile_removal_completed
		cmpl		NEXT(%esi), %edx
		je			element_deletion
		movl		NEXT(%esi), %esi
		jmp			missile_list_loop
		
		element_deletion:
		movl		NEXT(%edx), %edi
		movl		$0, NEXT(%edx)
		# Protect the caller save register
		pushl		%eax
		# Push the arg to mp1_free
		pushl		%edx
		call		mp1_free
		addl		$4, %esp
		popl		%eax
		movl		%edi, NEXT(%esi)
		
		jmp			missile_removal_completed

		head_deletion:
		movl		NEXT(%edx), %edi
		movl		$0, NEXT(%edx)
		# Protect the caller save register
		pushl		%eax
		# Push the arg to mp1_free
		pushl		%edx
		call		mp1_free
		addl		$4, %esp
		popl		%eax
		movl		%edi, %edx
		movl		%edx, mp1_missile_list
	
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

        movl        $base_alive, %esi
		# Offset = 160 * 24 + 2 * 18 = 3876
		update_first_city:
		movl		$3876, %eax
		cmpb		$0, 0(%esi)
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
		cmpb		$0, 1(%esi)
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
		cmpb		$0, 2(%esi)
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
		movl		$0x00010101, base_alive

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

# Is working but tasklet is broken
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
		jne			add_fail
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

# Is working
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
		cmpw		$0, crosshairs_x
		jg			check_if_x_too_large
		movl		$0, crosshairs_x
		jmp			check_if_y_too_small

		check_if_x_too_large:
		cmpw		$79, crosshairs_x
		jl			check_if_y_too_small
		movl		$79, crosshairs_x

		check_if_y_too_small:
		cmpw		$0, crosshairs_y
		jg			check_if_y_too_large
		movl		$0, crosshairs_y
		jmp			draw_crosshairs

		check_if_y_too_large:
		cmpw		$24, crosshairs_y
		jl			draw_crosshairs
		movl		$24, crosshairs_y

		# Draw a "plus" sign as crosshair at new position
		draw_crosshairs:
		movl		crosshairs_x, %eax
		movl		crosshairs_y, %ecx
		imull		$2, %eax
		imull		$160, %ecx
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

		# Load in the argument (address of the user space)
		movl		8(%ebp), %ebx
		movl		$4, %edi
		pushl		%edi
		call		mp1_malloc
		popl		%edi
		# Initialize the value passing to the user to 0
		movl		$0, %ecx
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
		cmpb		$0, (%edx)
		je		get_mp1_score
		addl		$1, %ecx

		get_mp1_score:
		shll		$16, %ecx
		movl		mp1_score, %esi
		addw		%si, %cx

		movl		%eax, %edx
		movl		%ecx, (%edx)
		
		# Pushing the parameters for mp1_copy_to_user function
		# mp1_copy_to_user (user address, from address, size)
		pushl		%edi
		pushl		%edx
		pushl		%ebx
		call		mp1_copy_to_user
		# Cleaning the stack memory pushed for mp1_copy_to_user
		popl		%ebx
		popl		%edx
		popl		%edi

		# Return value in the eax, if not 0 then copy failed
		cmpl		$0, %eax
		jne		copy_to_user_fail
		
		pushl		%edx
		call	mp1_free
		popl		%edx
		
		# Set the return value 0
		movl		$0, %eax

		# Restore stack frame and return		
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret

		copy_to_user_fail:

		pushl		%edx
		call	mp1_free
		popl		%edx
		
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

		# Linked list removal
		# head = head->next
		missile_list_loop_2:
		movl		mp1_missile_list, %ebx
		cmpl		$0, %ebx
		je			end_cleanup
		cmpl		$0, NEXT(%ebx)
		je			last_cycle
		movl		NEXT(%ebx), %ecx
		movl		%ecx, mp1_missile_list
		pushl		%ebx
		call		mp1_free
		popl		%ebx
		jmp			missile_list_loop_2
		
		last_cycle:
		pushl		%ebx
		call		mp1_free
		popl		%ebx
		movl		$0, mp1_missile_list

		end_cleanup:
		popl		%edi
		popl		%esi
		popl		%ebx
		leave
		ret
