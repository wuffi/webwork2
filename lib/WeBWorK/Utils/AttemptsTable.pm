#!/usr/bin/perl -w
use 5.012;

################################################################################
# WeBWorK Online Homework Delivery System
# Copyright © 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# $CVSHeader: webwork2/lib/WebworkClient.pm,v 1.1 2010/06/08 11:46:38 gage Exp $
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

=head1 NAME

lib/WeBWorK/Utils/AttemptsTable.pm

This file contains subroutines for formatting the table which reports the 
results of a student's attempt on a WeBWorK question.

=cut

use strict;
use warnings;
package WeBWorK::Utils::AttemptsTable;
use Class::Accessor 'antlers';
use Scalar::Util 'blessed';
use CGI;

# has answers     => (is => 'ro');
# has displayMode =>(is =>'ro');
# has imgGen      => (is =>'ro');

# Object contains hash of answer results
# Object contains display mode
# Object contains or creates Image generator
# object returns table
# object returns color map for answer blanks
# javaScript for handling the color map????


sub new {
	my $class = shift;
	$class = (ref($class))? ref($class) : $class; # create a new object of the same class
	my $rh_answers = shift;
	ref($rh_answers) =~/HASH/ or die "The first entry to AttemptsTable must be a hash of answers";
	my %options = @_; # optional:  displayMode=>, submitted=>, imgGen=>, ce=> 
	my $self = {
		answers      		=> $rh_answers,
		answerOrder         => $options{answerOrder},
		answersSubmitted    => $options{answersSubmitted}//0,
	    displayMode 		=> $options{displayMode} || "MathJax",
	    showAttemptPreviews => $options{showAttemptPreviews},
	    showAttemptResults 	=> $options{showAttemptResults},
	    showMessages 		=> $options{showMessages},
	    showCorrectAnswers  => $options{showCorrectAnswers}
	};
	bless $self, $class;
	$self->mk_ro_accessors(qw(answers answerOrder answersSubmitted displayMode imgGen));
	$self->mk_accessors(qw(correct_ids incorrect_ids));
	$self->mk_ro_accessors(qw(showAttemptPreviews showAttemptResults showMessages showCorrectAnswers));
	_init($self, %options);
	return $self;
}
sub _init {
	# verify display mode
	# build imgGen if it is not supplied 
	my $self = shift;
	my %options = @_;
	$self->{submitted}=$options{submitted}//0;
	$self->{displayMode} = $options{displayMode} || "MathJax";
	if ( $self->displayMode eq 'images') {
		if ( blessed( $options{imgGen} ) ) {
			$self->{imgGen} = $options{imgGen};
		} elsif ( blessed( $options{ce} ) ) {
			# build imgGen using $ce
			warn "building imgGen"; 
		} else {
			warn "Must provide image Generator (imgGen) or a course environment (ce) to build attempts table.";
		}
	}
}
sub formatAnswerRow {
	my $self          = shift;
	my $rh_answer     = shift;
	my $answerNumber  = shift;
	my $answerString  = $rh_answer->{original_student_ans}||'&nbsp;';
	my $answerPreview = $self->previewAnswer($rh_answer);
	my $correctAnswer = $rh_answer->{correct_ans}||'';
	
	my $answerMessage   = $rh_answer->{ans_message}||'';
	my $feedbackMessageClass = ($answerMessage eq "") ? "" : "FeedbackMessage";
	
	my $score         = (($rh_answer->{type}//'') eq 'essay') ?
						CGI::td({class => "UngradedResults"},"Not graded"): 
						  ($rh_answer->{score}) ? 
							CGI::td({class => "ResultsWithoutError"},"Correct") :
							CGI::td({class => "ResultsWithError"},"Incorrect");
	
	my $row = join('',
			  CGI::td({},$answerNumber) ,
			  CGI::td({},$answerString) ,
			  ($self->showAttemptPreviews)?  CGI::td({},$answerPreview):"" ,
			  ($self->showAttemptResults)?  $score :"" ,
			  ($self->showCorrectAnswers)?  CGI::td({},$correctAnswer):"" ,
			  ($self->showMessages)?        CGI::td({class=>$feedbackMessageClass},$self->nbsp($answerMessage)):"",
			  "\n"
			  );
	$row;
}

#####################################################
# determine whether any answers were submitted
# and create answer template if they have been
#####################################################

sub answerTemplate {
	my $self = shift;
	my $rh_answers = $self->{answers};
	my @tableRows=();
	my @correct_ids;
	my @incorrect_ids;

	push @tableRows, 	CGI::Tr(
			CGI::th("#"),
			CGI::th("Answer"),
			($self->showAttemptPreviews)? CGI::th("Preview"):'',
			($self->showAttemptResults)?  CGI::th("Score"):'',
			($self->showCorrectAnswers)?  CGI::th("CorrectAns"):'',
			($self->showMessages)?        CGI::th("Message"):'',
		);
	my $answerNumber     = 1;
	#FIXME need to use answer order variable, not sort.
    foreach my $ans_id (@{ $self->answerOrder() }) {  
        #FIXME -- need something more sophisticated to get the answer order correct
    	push @tableRows, $self->formatAnswerRow($rh_answers->{$ans_id}, $answerNumber++);
    	push @correct_ids,   $ans_id if $rh_answers->{$ans_id}->{score} >= 1;
    	push @incorrect_ids,   $ans_id if $rh_answers->{$ans_id}->{score} < 1;
    }
	my $answerTemplate = CGI::h3("Results for this submission") .
    	CGI::table({class=>"attemptResults"}, CGI::Tr(\@tableRows));
    $answerTemplate = "" unless $self->answersSubmitted; # only print if there is at least one non-blank answer
    $self->correct_ids(\@correct_ids);
    $self->incorrect_ids(\@incorrect_ids);
    $answerTemplate;
}
#################################################

sub previewAnswer {
	my $self =shift;
	my $answerResult = shift;
	my $displayMode = $self->displayMode;
	my $imgGen      = $self->imgGen;
	
	# note: right now, we have to do things completely differently when we are
	# rendering math from INSIDE the translator and from OUTSIDE the translator.
	# so we'll just deal with each case explicitly here. there's some code
	# duplication that can be dealt with later by abstracting out dvipng/etc.
	
	my $tex = $answerResult->{preview_latex_string};
	
	return "" unless defined $tex and $tex ne "";
	
	if ($displayMode eq "plainText") {
		return $tex;
	} elsif (($answerResult->{type}//'') eq 'essay') {
	    return $tex;
	} elsif ($displayMode eq "images") {
		$imgGen->add($tex);
	} elsif ($displayMode eq "MathJax") {
		return '<span class="MathJax_Preview">[math]</span><script type="math/tex; mode=display">'.$tex.'</script>';
	}
}

sub previewCorrectAnswer {
	my $self =shift;
	my $answerResult = shift;
	my $displayMode = $self->displayMode;
	my $imgGen      = $self->imgGen;
	
	my $tex = $answerResult->{correct_ans_latex_string};
	return $answerResult->{correct_ans} unless defined $tex and $tex=~/\S/;   # some answers don't have latex strings defined
	# return "" unless defined $tex and $tex ne "";
	
	if ($displayMode eq "plainText") {
		return $tex;
	} elsif ($displayMode eq "images") {
		$imgGen->add($tex);
		warn "adding $tex";
	} elsif ($displayMode eq "MathJax") {
		return '<span class="MathJax_Preview">[math]</span><script type="math/tex; mode=display">'.$tex.'</script>';
	}
}



sub color_answer_blanks {
	 my $self = shift;
	 my $out = join('', 
	 		  CGI::start_script({type=>"text/javascript"}),
	            "addOnLoadEvent(function () {color_inputs([\n  ",
		      join(",\n  ",map {"'$_'"} @{$self->{correct_ids}||[]}),
	            "\n],[\n  ",
		      join(",\n  ",map {"'$_'"} @{$self->{incorrect_ids}||[]}),
	            "]\n)});",
	          CGI::end_script()
	);
	return $out;
}

############################################
# utility subroutine -- prevents unwanted line breaks
############################################
sub nbsp {
	my ($self, $str) = @_;
	return (defined $str && $str =~/\S/) ? $str : "&nbsp;";
}



1;
