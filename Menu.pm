package Javascript::Menu;

use strict;
require bytes;

use CGI;
use NumberedTree;

use constant DEFAULT_STYLES => {caption => 'caption', 
				Mmenu => 'Mmenu', Smenu => 'Smenu'};

our $VERSION = '1.00';
our @ISA = qw(NumberedTree);

# package stuff:
my $cgi = CGI->new;    # Just for HTML shortcuts.
my $DBTree = 1;

# A default action generator. See the args passed to it:
my $default_action = sub {
    my $self = shift;
    my ($level, $unique) = @_;

    return '';
};

# <new> constructs a new tree or node.
# Arguments: By name: 
#            value - the value to be stored in the node.
#            action - a perl sub that is responsible for generating Javascript
#                     code to be executed on click. The sub will be called as 
#                     a method ($self->generator) so you have access to the
#                     object data when you construct the action.
#            legacy_encoding - forces the use of byte semantics in this object.
# Returns: The tree object.

sub new {
    my $parent = shift;
    my %args = @_;

    my $parent_serial;
    my $class;
    
    my $properties = $parent->SUPER::new($args{value});

    if ($class = ref($parent)) {
	$properties->{_Parent} = $parent->{_Serial};
	$properties->{Bytes} = $parent->{Bytes} ||= 0;
	$properties->{Action} = 
	    (exists $args{action}) ? $args{action} : $parent->{Action};  
    } else {
	$class = $parent;
	$properties->{_Parent} = 0;
	$properties->{Bytes} = $args{legacy_encoding} ||= 0;
	$properties->{Action} = 
	    (exists $args{action}) ? $args{action} : $default_action;  
    }

    $properties->{Action} = $default_action 
	unless(defined $properties->{Action});
    return $properties;
}

# <convert> takes a NumberedTree and makes it a Javascript::Menu.
# Arguments: By name:
#     tree - the tree to be converted to a menu.
#     action - an action generator, as described in <new>.
#     parent - (not for the user) sets the _Parent property.
#     legacy_encoding - forces the use of byte semantics in this object.
# Returns: the tree, modified and re-blessed as a Javascript::Menu.

sub convert {
    my $parent = shift;
    my $class = (ref($parent) or $parent);

    my %args = @_;
    my ($tree, $parent_num, $legacy) = 
	@args{'tree', 'parent', 'legacy_encoding'};
    my $def_action = (exists $args{action}) ? $args{action} : $default_action;
    $parent_num ||= 0;

    $tree->{Action} = $def_action;
    $tree->{_Parent} = $parent_num;

    for (@{ $tree->{Items} }) {
	$parent->convert(tree => $_, action => $def_action, 
			 parent => $tree->getNumber, 
			 legacy_encoding => $legacy);
    }
    return bless $tree, $class;
}

# <readDB> constructs a new Javascript::Menu from a table in a DB using 
#  NumberedTree::DBTree.
# Arguments: By name:
#     source_name - table name.
#     source - a DB handle to work with.
#     action - an action generator, as described in <new>.
#     legacy_encoding - forces the use of byte semantics in this object.
# Returns: the tree, modified and re-blessed as a Javascript::Menu.

sub readDB {
    my $parent = shift;
    my $class = (ref($parent) or $parent);
    my %args = @_;

    my ($table, $dbh, $legacy) = 
	@args{'source_name', 'source', 'legacy_encoding'};
    my $def_action = (exists $args{action}) ? $args{action} : $default_action;
    return undef unless ($table && $dbh);

    require NumberedTree::DBTree; 
    my $tree = NumberedTree::DBTree->read($table, $dbh);
    $tree->revert;
    return $class->convert(tree => $tree, action => $def_action, 
			   legacy_encoding => $legacy);
}

# <getHTML> returns the HTML and Javascript that show the menu.
# Arguments: By name:
#     styles - alternative set of styles. Default will be used if this isn't
#              supplied or malformed.
#     caption - a starting caption. Optional.
# Returns: In list context returns a list of HTML lines to print. In scalar
#     context returns a reference to same list.

sub getHTML {
    my $self = shift;
    bytes->import if $self->{Bytes};

    my %args = @_;
    my $caption = (exists $args{caption}) ? $args{caption} : $self->getValue;
    my $styles = $args{styles};
    $styles = DEFAULT_STYLES unless(ref $styles eq 'HASH' 
				    and $styles->{caption} 
				    and $styles->{Mmenu} 
				    and $styles->{Smenu});
    my $unique = $self->getUniqueId;
    my $action = $self->{Action}->($self, -1, $unique);
    my @html; # return value.

    push @html, $cgi->div({-class => $styles->{caption},
			   -id => "caption_$unique",
			   -onMouseOver => "showMenu(1, 0, 'main_$unique', " .
			       "this, 'main_$unique')",
			   -onMouseOut => "outOfMenu()",
			   -onClick => $action
			   }, $caption);
    $self->buildTable(1, 0, $unique, \@html, %$styles);

    return @html if (wantarray);
    return \@html;
}

# Helper for <getHTML> (actually does the real work).
#  Recursively builds tables for each submenu and pushes the HTML into
#  @html which is used as a stack.
# Arguments: $ismain - used to determine table style.
#            $level - the submenu's level (main is 0),
#            $unique - the menue's unique identifier. This is an argument so 
#                      changing the uniquifing rule, will only be in <getHTML>.
#            $id - The menu's HTML name, used for identification by JavaScript 
#                  functions.
#            $html - a reference to the stack.
#            %styles - a hash of style names.
# Returns: Nothing. Modifies buffer directly.

sub buildTable {
    my $self = shift;
    my $serial = $self->{_Serial};
    my ($ismain, $level, $unique, $html, %styles) = @_;
    
    my $style = ($ismain) ? $styles{Mmenu} : $styles{Smenu};
    my $name = ($ismain) ? "main_$unique" : "s_${serial}_$unique";
    my $htmlstr = $cgi->start_table({-class => $style, -id => $name});
    my $next_level = $level + 1;

    # '~' is a placeholder
    my $GonMouse = "showMenu(0, ~1, 's_~2_$unique', this, 'main_$unique');";
    my $GonClick = $self->{Action};
    
    while (my $item = $self->nextNode) {
	bytes->import if $self->{Bytes};

	my $onMouse = $GonMouse;
	my $onClick = $GonClick->($item, $level, $unique);

	if ($item->childCount) {
	    # '~1' = _next_ menu's level. '~2' = branch serial.
	    $onMouse =~ s/~2/$item->{_Serial}/;          
	    $onMouse =~ s/~1/$next_level/e; 

	    $item->buildTable(0, $next_level, $unique, $html, %styles);
	} else {$onMouse = "stopTimer();hideMenus($next_level);";}

	$onClick .= '; ' if ($onClick and $onClick !~ /;$/);
	$htmlstr .= $cgi->Tr($cgi->td({-onMouseOver => $onMouse,
				       -onClick => "${onClick}hideMenus(0)",
				       -onMouseOut => "outOfMenu()"}, 
				      $item->{Value} ));
    }
    $htmlstr .= $cgi->end_table;
    push @$html, $htmlstr;
}

# <append> adds a node to the tree, at the end of the Items array.
# Arguments: $value - the caption of the new node.
#            $action - an action to assign to the item. undef is allowed. To
#                use the parent's action pass '0'.
# Returns: The new node.

sub append {
    my $self = shift;
    my ($value, $action) = @_;
    my %args = (value => $value);

    $args{action} = $action unless ($action eq '0');
    my $newNode = $self->new(%args);

    return undef unless $newNode;

    push @{$self->{Items}}, $newNode;
    return $newNode;
}

# <getUniqueId> returns the html suffix id of the menu.
# Arguments: None.
# Returns: A unique suffix for HTML names which includes the lucky number and
#          the root node's serial number.

sub getUniqueId {
    my $self = shift;
    return "$self->{_LuckyNumber}__$self->{_Serial}";
}

# <useBytes> and <noBytes> change the boolean flag that determines whether 
#  byte semantics should be used when processing that item.
# Arguments: None.
# Returns: Nothing.

sub useBytes {
    my $self = shift;
    $self->{Bytes} = 1;
}

sub noBytes {
    my $self = shift;
    $self->{Bytes} = 0;
}

# <setAction> sets the action on an item. if no action is given, the default 
#  do-nothing action is used.
# Arguments: $action - an action, or nothing - implies default.
# Returns: Nothing.

sub setAction {
    my $self = shift;
    my $action = shift;
    
    $action ||= $default_action;
    $self->{Action} = $action;
}

sub getAction {
    my $self = shift;
    return $self->{Action};
}

#**************************************************************
#   Class methods for generating required JavaScript and CSS.

# <baseCSS> returns the base style to be used with this module - some 
#  definitions are esential, such as visibility. Note that using just the base
#  style will yield a transparent and ugly menu.
# Arguments: None.
# Returns: a hash containing for each required element (caption, Mmenu, 
#          Smenu) another hash with property - value pairs. modify at will,
#          then print map {"$_: $hash->{$_};"} keys $hash; where $hash is the 
#          properties hash for an element.

sub baseCSS {
    my $self = shift; # Never used - class method.
    return {caption => {},
	    Mmenu => {position => 'absolute', top => '1', left => '1', 
		      'z-index' => 10, visibility => 'hidden'},
	    Smenu => {position => 'absolute', top => '1', left => '1', 
		      'z-index' => 10, visibility => 'hidden'}
	    };
} 

# <reasonableCSS> does the same thing as <baseCSS> only with more properties.
# Arguments: None.
# Returns: See <baseCSS>.

sub reasonableCSS {
    my $self = shift; # Never used - class method.
    return {caption => {border => 'solid 1px black',
			background => 'blue', width => '10%', 
			color => 'white', 'font-weight' => 'bold'},
	    Mmenu => {position => 'absolute', top => '1', left => '1', 
		      background => 'cyan', 'z-index' => 10, 
		      visibility => 'hidden'},
	    Smenu => {position => 'absolute', top => '1', left => '1', 
		      background => 'cyan', 'z-index' => 10, 
		      visibility => 'hidden'}
	    };
} 

sub buildCSS {
    my $self = shift; # Never used - class method.
    my $raw_css = shift;
    my $css = '';
    
    for my $class (keys %$raw_css) {
	my %props = %{ $raw_css->{$class} };
	$css .= ".$class {\n";
	$css .= join "\n", map {"\t$_: $props{$_};"} keys %props;
	$css .= "\n}\n\n";
    }
    return $css;
}

# <baseJS> generates required Javascript code for use with this module.
# Arguments: $rtl - if right-to-left menu.
# Returns: Only the code. You can put this inside a <script> tag or print
#          to a .js file.

sub baseJS {
    my $self = shift; # Never used.
    my $rtl = shift;

    my ($place, $right_anchor, $right_anchor_mo);
    if ($rtl) {
	$place = '- smenu.offsetWidth - 4';
	$right_anchor = '(smenu.offsetWidth - caller.offsetWidth)';
    } else {
	$place =  '+ caller.offsetWidth + 4';
	$right_anchor = '0';
    }
    return <<EndJS;
//functions for a dynamic tree-menu.
//Main menu (child of the BOX) is in level 0.
//Every menu passes to showMenu the number of the *next* level.
// (this is done by Perl, baby...)

var openMenus = new Array();	//A stack of open menus.
var collapseMenusTimer;		//Next two vars used for closing all menus.
var isCollapsing = false;

function getCrossBrowser(name) {
	return document.getElementById(name); //Now it works on all of them...
}

function showMenu (isMain, level, name, caller, coordSpaceId) {
	var smenu = getCrossBrowser(name);
        var coordSpace = getCrossBrowser(coordSpaceId);

	if (isCollapsing) {
		clearTimeout(collapseMenusTimer);
		isCollapsing = false;
	}
	
	//Now that that is out of the way...
	hideMenus(level);
	smenu.style.visibility = "visible";

	if (isMain) {
	        smenu.style.left =  findPosX(caller, coordSpace) - 
		    $right_anchor + "px";
	        smenu.style.top = findPosY(caller, coordSpace) + 
		    caller.offsetHeight + "px"; 
	} else {
		smenu.style.top = findPosY(caller, coordSpace) + "px";
		smenu.style.left = findPosX(caller, coordSpace) $place + "px";
	}
	openMenus.push(smenu);
}

function hideMenus(level) {
	for (i = openMenus.length - 1; i >= level; i--) {
		openMenus[i].style.visibility = "hidden";
		openMenus.pop();
	}
}

function outOfMenu() {
	if (isCollapsing) {
		clearTimeout(collapseMenusTimer);
		isCollapsing = false;
	}

	collapseMenusTimer = setTimeout("hideMenus(0)",500);
	isCollapsing = true;
}

function stopTimer() {
	if (isCollapsing) {
		clearTimeout(collapseMenusTimer);
		isCollapsing = false;
	}
}

//Two functions for finding absolute position of an element on the page:
//coordSpace is the item whose parent determines the coordinate space.

function findPosX(obj, coordSpace) {
	var curleft = 0;
	if (obj.offsetParent)
	{
		while(obj.offsetParent)
		{
		        curleft += obj.offsetLeft
		        if (obj.offsetParent == coordSpace.offsetParent)
			    break;
			obj = obj.offsetParent;
		}
	}
	else if (obj.x)
		curleft += obj.x;
	return curleft;
}

function findPosY(obj, coordSpace) {
	var curtop = 0;
	if (obj.offsetParent)
	{
		while (obj.offsetParent)
		{
			curtop += obj.offsetTop
		        if (obj.offsetParent == coordSpace.offsetParent)
			    break;
			obj = obj.offsetParent;
		}
	}
	else if (obj.y)
		curtop += obj.y;
	return curtop;
}

EndJS

}

1;

=head1 NAME

 Javascript::Menu - a NumberedTree that generates HTML and Javascript code for
 a menu.

=head1 SYNOPSIS

  use Javascript::Menu;

  # Give it something to do (example changes the menu's caption):
  my $action = sub {
    my $self = shift;
    my ($level, $unique) = @_;
    
    my $value = $self->getValue;
    return "caption_${unique}.innerHTML='$value'";
  };

  # Build the tree (examples use legacy encoding!):
  my $menu = Javascript::Menu->convert(tree => $otherTree, action => $action,
                                       legacy_encoding => 1);
  
  my $menu = Javascript:Menu->readDB(source_name => $table, source => $dbh,
                                     action => $action, legacy_encoding => 1);
  
  my $menu = Javascript::Menu->new(value => 'Please select a parrot', 
                                   action => $action, legacy_enciding => 1);
  my $blue = $menu->append('Norwegian Blue');
  $blue->append('Pushing up the daisies');
  $menu->append('A Snail');

  # Print it out:
  my $css = $menu->buildCSS($menu->reasonableCSS);
  print $cgi->start_html(-script => $menu->baseJS('rtl'), 
                         -style => $css); #CSS plays an important role. 
  print $tree->getHTML;
  
=head1 DESCRIPTION

Javascript::Menu is an object that helps in creating the HTML, Javascript, and some of the CSS required for a table-based Menu. There are a few other modules that deal with menus, But as I browsed through them, I found that none of them exactly fitted my needs. So I designed this module, with the following goals in mind:

=over 4

=item Flexibility

The main feature of this module is the ability to supply all nodes or any specific node with a subroutine that is activated in time of the code generation to help decide what the item will do when it is clicked. This allows customisation far beyond associating a link with every item. Multy-level selection menus become very easy to do (and this is, in fact, what I needed when I started writing this).

=item I18n

Working with i18n (internationalization) can be a big headache. Working with Hebrew (or Arabic) forces you not only to change your charachters, but also to change your direction of writing. I incorporated into this module native support for legacy ASCII-based encodings, as well as the ability to produce right-to-left menus. 

=item Object Hierarchy

I designed the module to work with two other modules of mine, NumberedTree and NumberedTree::DBTree, which simplify the task of building the menu and allow for construction of a menu from database information.

=back

Being it the first version of the module, perhaps some features are missing, but having used the module for my own needs, I found the module as good as to release it on CPAN. You'll find that having made some preliminary steps, like tweaking the CSS to look the way you like it to, the rest is fairly easy.

So, how do we use this module?

=head2 What should I expect to see?

The generated menu will be visible as a div that shows the caption line for the menu. As you hover with the mouse over the caption, the main menu will appear under the caption. Hovering over any item with childs will open a sub-menu either to the right or left of the main menu, depending on the direction you chose for the menu. Clicking on any item will hide all menus, leaving only the caption, and fire the action you assigned to the item.

=head2 Some naming rules.

The following rules decide on the names (id attributes) of generated HTML elements:

Every generated menu recieves a unique suffix. Let's call this $unique. this is added to the name of  every part of the same menu.

Every node has a number, unlike any other node on the same tree. Let's call that $number. For reasons why, see the documentation for NumberedTree or just read on.

The caption line is called caption_$unique.
The main menu is called main_$unique.
Every sub menu is called s_$number_$unique.

=head2 CSS classes

Every part of the menu is associated with a class name, that defines its style (the class attribute). By default the caption's class is 'caption', the main menu's class is 'Mmenu' and sub menus get the class 'Smenu'. If this does not suit you, you are welcome to create the menu with different style associations (see B<getHTML>).

=head2 Setting up the supporting code

Javascript::Menu requires some supporting code to work. First, as implied by its name, certain Javascript functions must be available. This is, however, the easiest thing to set up. The code is returned in its entirety, as one gigant multiline string, by the class method I<baseJS> (see below). use this in your head tag, or do like me and dump this to a .js file.

The second thing that needs to be set up is the CSS. except for a few settings, you are pretty free to style the menu as you see fit, but that also means some work for you. The class method I<baseCSS> returns only the basic settings, those you can't change. You must tweak it some more to look good. The class method I<reasonableCSS> returns some example CSS that doesn't look too bad. Again, you should tweak this as described below under I<baseCSS>. Finally, I included a convenience class method called I<buildCSS> that stringifies the data structure supplied by these two functions into valid CSS. 

=head2 Building the tree

To get the tree that represents the structure of the menu, you have 3 ways:

=over 4

=item The hard way: Javascript::Menu->new

This builds the root node, with your desired value and action (which will be the default for all children of this node). You add nodes with $tree->I<append>, and descend the hierarchy using methods found in the parent class - NumberedTree. For each element you supply the value (what is shown on the screen) and possibly an action.

=item The easier way: Javascript::Menu->convert

This just takes an existing NumberedTree and blesses it as a Menu, adding an action to each node. This is easier if you already have the data structure for something else, and you want to make a menu out of it..

=item A nice shortcut: Javascript::Menu->readDB

If you have the module NumberedTree::DBTree (another one of mine) and you use it to store trees in a database, this method allows you to read such table directly and convert it to a menu. This is extremely useful, trust me :)

=back

=head2 But what are these actions and how do I generate them?

An action is basically a piece of Javascript code that is executed when the user clicks on an item. It is added to the onClick attribute of the item. However, actions in this module are not plain strings. Instead, an action is a subroutine reference that is called when the item's HTML code is being processed. It does what it does, then returns a string containing the Javascript code. In order for this sub to be able to do anything useful, it gets 3 arguments passed to it:

=over 4

=item 1 

A reference to the node being processed, so you can get information on the node via object methods.

=item 2 

The item's level in the hierarchy - the main menu is at level 0, the caption is at level -1.

=item 3 

The menu's unique suffix.

=back 

To make an item do nothing except for showing its submenu, use $item->I<setAction>

=head2 Printing the HTML

Now all you have to do is $tree->getHTML. this will return an array so you can shift out the caption and locate it inside some div while the rest of the menu is located outside, avoiding width constraints. You can also push other stuff inside and create a widget for your script.

=head1 METHODS

This section only describes methods that are not the same as in NumberedTree. Obligatory arguments are marked.

=head2 Constructors

There are three of them:

=over 4

=item new (I<value> => $value, action => $action, legacy_encoding => 1)

Creates a new tree with one root element., whose text is specified by the value argument. If an action is not supplied, then the package's default do-nothig action will be used. You'll have to add nodes manually.
If legacy_encoding is supplied and true, getHTML will use bytes semantics (that's good for ASCII-derived encodings) when called.

=item convert (I<tree> => $tree, action => $action, legacy_encoding => 1)

Converts a tree (given in the I<tree> argument) into an instance of Javascript::Menu. You will lose the original tree of course, so if you still need it, first use $tree->clone (see NumberedTree.pm).

As in new, if action is not specified, one will be created for you. legacy_encoding is also explained in new.

=item readDB (I<source_name> => $table, I<source> => $dbh, action => $action, legacy_encoding => 1);

Creates a new menu from a table that contains tree data as specified in NumberedTree::DBTree. Arguments are the same as to I<new>, except for the required source_name, which specifies the name of the table to be read, and source, which is a DBI database handle.

=back

=head2 getHTML (styles => $styles, caption => 'altCaption')

This method returns the HTML for a menu whose caption is the node the method was invoked on. The menu's caption will be the root element's value unless the caption argument is given.

the optional styles argument allows you to change default style names described above. This should be a hash reference, with a key for each style, specifying the new name. Like:

$styles = { caption => 'mycap', Mmenu => 'myM', Smenu => 'myS' };

=head2 Accessors

Javascript::Menu adds to the methods of its base class the following accessors:

=over 4

=item getUniqueId

Returns the unique Id that the menu will recieve when built with this node as root.

=item useBytes / noBytes

Specifies whether byte semantics should be used when the node is processed. Has the same effect as the legacy_encoding option in the constructors.

=item getAction / setAction ($action)

gets and sets the item's action. If no action is given to setAction, the default do-nothing action is used.

=back

=head2 Class methods

The following class methods help you generate supporting code for your menus:

=over 4

=item baseJS ($rtl)

Returns the basic Javascript code for use with this module. If the optional $rtl is true, the code will generate right-to-left menus.

=item baseCSS

Returns the minimum required CSS for the menu to work properly, as a reference to the following data structure: A main hash with one key for each element of the menu (caption, main menu, sub menus). The value for each key is again a hash with CSS property - value pairs, like top => 1, left => 1 etc. It is up to you to add properties to this structure to make your menu look good.

=item reasonableCSS

Returns the same data structure as in baseCSS, only with more properties. Using the properties provided by this function will result in a black-bordered, blue caption box with white text, and cyan menus with black text. Again, you can tweak this to your satisfaction.

=item buildCSS ($css)

Takes the data structure described in I<baseCSS> and returns a string with valid CSS you can incorporate into your document.

=head1 BROWSER COMPATIBILITY

Tested on IE6 and Mozilla 1.4 and worked. If you test it on other browsers, please let me know what is the result.

=head1 BUGS

Please report through CPAN: 
E<lt>http://rt.cpan.org/NoAuth/Bugs.html?Dist=NumberedTreeE<gt>
or send mail to E<lt>bug-NumberedTree#rt.cpan.orgE<gt> 

=head1 SEE ALSO

NumberedTree, NumberedTree::DBTree
For an explanation of i18n and l10n in perl see perlunicode, bytes.pm, perllocale.

=head1 AUTHOR

Yosef Meller, E<lt>mellerf@netvision.net.ilE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Yosef Meller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut