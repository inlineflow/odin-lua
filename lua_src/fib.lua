-- Function to generate a Fibonacci sequence of 'n' terms and store them in a table
function generate_fibonacci(n)
	-- Create an empty table to store the sequence
	local fib_sequence = {}

	-- Handle edge cases for n = 0, 1, 2
	if n <= 0 then
		return fib_sequence
	elseif n >= 1 then
		fib_sequence[1] = 0 -- The sequence typically starts with 0, 1
	end
	if n >= 2 then
		fib_sequence[2] = 1
	end

	-- Use a loop to calculate subsequent numbers
	for i = 3, n do
		-- Each number is the sum of the two preceding ones
		fib_sequence[i] = fib_sequence[i - 1] + fib_sequence[i - 2]
	end

	return fib_sequence
end

-- Specify how many Fibonacci numbers you want to generate
local num_terms = 15
local fib_table = generate_fibonacci(num_terms)

-- Print the generated sequence from the table
-- print("Fibonacci sequence up to term " .. num_terms .. ":")
-- for index, value in ipairs(fib_table) do
-- 	print("Term " .. index .. ": " .. value)
-- end

-- Example of accessing a specific number from the table
-- local term_index = 10
-- if fib_table[term_index] ~= nil then
-- 	print("\nThe Fibonacci number at index " .. term_index .. " is: " .. fib_table[term_index])
-- end

local result = "The Fibonacci number at index " .. #fib_table .. " is: " .. fib_table[#fib_table]
print("look mama I'm printing", "I'm printing hard")
return result
